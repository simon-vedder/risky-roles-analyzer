"""Drive the sample report in headless Chrome over the DevTools protocol and check the interactive parts:
filters, search, sort, selection, removal command popup, clipboard copy, cleanup popup, accept/hide, CSV export."""
import asyncio, json, os, subprocess, sys, time, urllib.request
import websockets

CHROME = "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
PORT = 9333
URL = sys.argv[1] if len(sys.argv) > 1 else "http://127.0.0.1:8765/report.html"   # serve docs/sample with: python3 -m http.server 8765 --bind 127.0.0.1
PROFILE = os.path.join(os.environ.get("TMPDIR", "/tmp"), "rra-report-ui-chrome-profile")

results = []
def check(name, ok, detail=""):
    results.append((name, bool(ok), detail))
    print(("PASS  " if ok else "FAIL  ") + name + (f"  [{detail}]" if detail and not ok else ""))

class CDP:
    def __init__(self, ws): self.ws, self.n, self.exceptions, self.console = ws, 0, [], []
    async def call(self, method, **params):
        self.n += 1; my = self.n
        await self.ws.send(json.dumps({"id": my, "method": method, "params": params}))
        while True:
            msg = json.loads(await self.ws.recv())
            if msg.get("id") == my:
                if "error" in msg: raise RuntimeError(f"{method}: {msg['error']}")
                return msg.get("result", {})
            self.on_event(msg)
    def on_event(self, msg):
        m = msg.get("method")
        if m == "Runtime.exceptionThrown": self.exceptions.append(msg["params"]["exceptionDetails"].get("exception", {}).get("description", str(msg["params"])))
        elif m == "Runtime.consoleAPICalled" and msg["params"]["type"] in ("error", "warning"):
            self.console.append(" ".join(str(a.get("value", a.get("description", ""))) for a in msg["params"]["args"]))
    async def js(self, expr, await_promise=False):
        r = await self.call("Runtime.evaluate", expression=expr, returnByValue=True, awaitPromise=await_promise)
        if "exceptionDetails" in r: raise RuntimeError(r["exceptionDetails"].get("exception", {}).get("description", str(r["exceptionDetails"])))
        return r.get("result", {}).get("value")
    async def drain(self, seconds=0.3):
        end = time.time() + seconds
        while time.time() < end:
            try: self.on_event(json.loads(await asyncio.wait_for(self.ws.recv(), timeout=end - time.time())))
            except (asyncio.TimeoutError, ValueError): break

async def main():
    proc = subprocess.Popen([CHROME, "--headless=new", "--disable-gpu", f"--remote-debugging-port={PORT}", "--remote-allow-origins=*",
                             f"--user-data-dir={PROFILE}", "--no-first-run", "--window-size=1400,1000", "about:blank"],
                            stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    try:
        for _ in range(50):
            try:
                targets = json.load(urllib.request.urlopen(f"http://127.0.0.1:{PORT}/json/list")); break
            except Exception: time.sleep(0.2)
        page = next(t for t in targets if t["type"] == "page")
        async with websockets.connect(page["webSocketDebuggerUrl"], max_size=50_000_000) as ws:
            cdp = CDP(ws)
            await cdp.call("Runtime.enable"); await cdp.call("Page.enable")
            origin = URL.split("/report.html")[0]
            await cdp.call("Browser.grantPermissions", origin=origin, permissions=["clipboardReadWrite", "clipboardSanitizedWrite"])
            await cdp.call("Page.navigate", url=URL)
            for _ in range(50):
                if await cdp.js("document.readyState") == "complete" and await cdp.js("typeof DATA !== 'undefined'"): break
                await asyncio.sleep(0.2)
            await cdp.drain(0.5)

            total = await cdp.js("DATA.length")
            rows = await cdp.js("document.querySelectorAll('#data tbody tr').length")
            check("report loads with one row per finding", total > 0 and rows == total, f"DATA={total} rows={rows}")
            check("count line shows all findings", await cdp.js("document.getElementById('count').textContent") == f"{total} of {total} findings")
            check("subtitle names the tenant", "Contoso" in (await cdp.js("document.getElementById('subtitle').textContent")))
            check("no external resources referenced", await cdp.js("[...document.querySelectorAll('script[src],link[href],img[src]')].filter(e => /^https?:/.test(e.src || e.href)).length") == 0)
            protected_total = await cdp.js("DATA.filter(r => r.Protected).length")
            check("protected rows have a disabled checkbox, others enabled",
                  await cdp.js("[...document.querySelectorAll('#data .select-cb')].filter(cb => cb.disabled).length") == protected_total
                  and await cdp.js("[...document.querySelectorAll('#data tbody tr')].every(tr => { const r = DATA.find(d => d.Id === tr.dataset.id); return r.Protected === tr.querySelector('.select-cb').disabled; })"))
            check("summary cards rendered with numbers", await cdp.js("document.querySelectorAll('#summary .card, #summary > *').length") >= 8)

            fire = "el.dispatchEvent(new Event('input', {bubbles: true})); el.dispatchEvent(new Event('change', {bubbles: true}));"
            async def setf(id_, value): await cdp.js(f"(() => {{ const el = document.getElementById('{id_}'); el.value = {json.dumps(value)}; {fire} }})()")
            async def reset():
                for id_ in ["search", "filterScope", "filterAssignment", "filterPrincipal", "filterRole", "filterVia", "filterCustom", "filterStatus", "filterSeverity", "filterProtected"]:
                    await setf(id_, "")
            visible = "[...document.querySelectorAll('#data tbody tr')].map(tr => DATA.find(d => d.Id === tr.dataset.id))"

            await setf("filterSeverity", "High")
            check("severity filter keeps only High and Critical", await cdp.js(f"{visible}.length > 0 && {visible}.every(r => ['High','Critical'].includes(r.Severity))"))
            check("count line reflects the filter", await cdp.js("/^\\d+ of \\d+ findings$/.test(document.getElementById('count').textContent) && !document.getElementById('count').textContent.startsWith('%d of')" % total))
            await reset()
            await setf("filterProtected", "protected")
            check("protected filter shows only protected rows", await cdp.js(f"{visible}.length === {protected_total} && {visible}.every(r => r.Protected)"))
            await setf("filterProtected", "removable")
            check("removable filter shows only unprotected rows", await cdp.js(f"{visible}.length === DATA.length - {protected_total} && {visible}.every(r => !r.Protected)"))
            await reset()
            await setf("filterVia", "group")
            check("via-group filter shows only inherited rows", await cdp.js(f"{visible}.length > 0 && {visible}.every(r => r.ViaGroup)"))
            await reset()
            await setf("filterAssignment", "Activated")
            check("Activated (PIM) filter finds the activation", await cdp.js(f"{visible}.length > 0 && {visible}.every(r => r.AssignmentType === 'Activated' && r.Protected)"))
            await reset()
            await setf("filterCustom", "custom")
            check("custom-role filter shows CUSTOM flagged rows only", await cdp.js(f"{visible}.length > 0 && {visible}.every(r => r.IsCustomRole) && document.querySelectorAll('#data .custom-flag').length === {visible}.length"))
            await reset()
            await setf("filterStatus", "inactive")
            check("inactive filter shows disabled / dormant principals only", await cdp.js(f"{visible}.length > 0 && {visible}.every(r => INACTIVE.includes(r.ActivityStatus))"))
            await reset()
            name = await cdp.js("DATA.find(r => !r.Protected).PrincipalName")
            await setf("search", name[:6].lower())
            check("search matches principal names case-insensitively", await cdp.js(f"{visible}.length > 0 && {visible}.every(r => [r.PrincipalName, r.UPN, r.RoleName, r.ScopeName, r.ViaGroup, r.PrincipalId].filter(Boolean).join(' ').toLowerCase().includes({json.dumps(name[:6].lower())}))"))
            await setf("search", "zzz-no-such-thing")
            check("empty state appears when nothing matches", await cdp.js("document.querySelectorAll('#data tbody tr').length === 0 && document.getElementById('empty').style.display === 'block'"))
            await reset()
            check("reset returns to all findings", await cdp.js("document.querySelectorAll('#data tbody tr').length") == total)

            await cdp.js("document.querySelector('th[data-key=\"PrincipalName\"]').click()")
            check("sorting by principal name ascending", await cdp.js(f"(() => {{ const v = {visible}.map(r => r.PrincipalName.toLowerCase()); return v.every((x, i) => i === 0 || v[i-1] <= x); }})()"))
            await cdp.js("document.querySelector('th[data-key=\"PrincipalName\"]').click()")
            check("second click flips to descending", await cdp.js(f"(() => {{ const v = {visible}.map(r => r.PrincipalName.toLowerCase()); return v.every((x, i) => i === 0 || v[i-1] >= x); }})()"))
            await cdp.js("document.querySelector('th[data-key=\"RiskScore\"]').click(); document.querySelector('th[data-key=\"RiskScore\"]').click()")
            check("risk score sort descending puts the highest first", await cdp.js(f"(() => {{ const v = {visible}.map(r => parseFloat(r.RiskScore)); return v.every((x, i) => i === 0 || v[i-1] >= x); }})()"))

            check("copy button disabled with nothing selected", await cdp.js("document.getElementById('copyRemoval').disabled === true && document.getElementById('selectionCount').textContent === '0 selected'"))
            await cdp.js("document.getElementById('selectVisible').click()")
            removable = total - protected_total
            check("Select visible selects every unprotected row", await cdp.js("document.getElementById('selectionCount').textContent") == f"{removable} selected"
                  and await cdp.js("document.querySelectorAll('#data .select-cb:checked').length") == removable
                  and await cdp.js("document.querySelectorAll('#data tbody tr.selected').length") == removable)
            check("copy button enabled after selecting", await cdp.js("document.getElementById('copyRemoval').disabled") is False)
            await cdp.js("document.getElementById('copyRemoval').click()")
            cmd = await cdp.js("document.getElementById('popup').style.display === 'block' ? document.getElementById('removalText').textContent : ''")
            ids = await cdp.js("DATA.filter(r => !r.Protected).map(r => r.Id)")
            check("removal popup opens with the module command", "Remove-RiskyRoleAssignment -WhatIf" in cmd and "$findings | Where-Object Id -in @(" in cmd)
            check("removal command lists every selected id, quoted", all(f"'{i}'" in cmd for i in ids) and f"{removable} assignment(s)" in cmd)
            check("removal command never contains a protected id", not any(f"'{i}'" in cmd for i in (await cdp.js("DATA.filter(r => r.Protected).map(r => r.Id)"))))
            await cdp.call("Emulation.setFocusEmulationEnabled", enabled=True)
            await cdp.call("Page.bringToFront")
            await cdp.js("document.querySelector('#popupBody [data-copy-from=\"removalText\"]').click()")
            await asyncio.sleep(0.4)
            label = await cdp.js("document.querySelector('#popupBody [data-copy-from=\"removalText\"]').textContent")
            try: clip = await cdp.js("navigator.clipboard.readText()", await_promise=True)
            except RuntimeError as e: clip = f"<readText failed: {e}>"
            check("Copy button reports Copied (clipboard write resolved)", label == "Copied", f"label={label!r}")
            check("clipboard holds exactly the removal command", clip == cmd, f"clip={clip[:80]!r}")
            await cdp.js("document.getElementById('popupClose').click()")
            check("popup closes with the X", await cdp.js("document.getElementById('popup').style.display") == "none")
            await cdp.js("document.getElementById('clearSelection').click()")
            check("Clear empties the selection and disables the copy button", await cdp.js("document.getElementById('selectionCount').textContent === '0 selected' && document.getElementById('copyRemoval').disabled && document.querySelectorAll('#data .select-cb:checked').length === 0"))

            await cdp.js("document.querySelector('#data .select-cb:not(:disabled)').click()")
            check("single checkbox selects one row", await cdp.js("document.getElementById('selectionCount').textContent") == "1 selected")
            await setf("filterSeverity", "Critical"); await reset()
            check("selection survives filtering", await cdp.js("document.getElementById('selectionCount').textContent") == "1 selected")
            await cdp.js("document.getElementById('clearSelection').click()")

            await cdp.js("(() => { const tr = [...document.querySelectorAll('#data tbody tr')].find(tr => DATA.find(d => d.Id === tr.dataset.id).ViaGroup); tr.querySelector('.cleanup-btn').click(); })()")
            body = await cdp.js("document.getElementById('popup').style.display === 'block' ? document.getElementById('popupBody').innerText : ''")
            check("cleanup popup for an inherited row offers option A (member) and option B (group)", "Option A" in body and "Option B" in body and "inherits this role through group" in body)
            check("inherited row is protected: module command not offered", "Protected:" in body and "Remove-RiskyRoleAssignment" not in body)
            await cdp.js("document.getElementById('popupClose').click()")
            await cdp.js("(() => { const tr = [...document.querySelectorAll('#data tbody tr')].find(tr => { const r = DATA.find(d => d.Id === tr.dataset.id); return !r.Protected && r.RoleScope === 'Entra'; }); tr.querySelector('.cleanup-btn').click(); })()")
            body = await cdp.js("document.getElementById('popupBody').innerText")
            check("cleanup popup for a removable Entra row shows the write-scope prerequisite and the module command", "RoleManagement.ReadWrite.Directory" in body and "Remove-RiskyRoleAssignment -WhatIf" in body and "Native command" in body)
            await cdp.js("document.body.click()")
            check("click outside closes the popup", await cdp.js("document.getElementById('popup').style.display") == "none")

            await cdp.js("document.querySelector('#data .accept-cb').click()")
            check("accepting a finding hides it and counts it", await cdp.js("document.querySelectorAll('#data tbody tr').length") == total - 1 and "(1 accepted)" in (await cdp.js("document.getElementById('count').textContent")))
            await cdp.js("document.getElementById('toggleAccepted').click()")
            check("Show accepted brings it back, greyed", await cdp.js("document.querySelectorAll('#data tbody tr').length") == total and await cdp.js("document.querySelectorAll('#data tbody tr.accepted').length") == 1
                  and await cdp.js("document.getElementById('toggleAccepted').textContent") == "Hide accepted")
            await cdp.js("document.querySelector('#data tbody tr.accepted .accept-cb').click(); document.getElementById('toggleAccepted').click()")

            await cdp.call("Browser.setDownloadBehavior", behavior="deny")
            await cdp.js("document.getElementById('exportCsv').click()")
            await cdp.drain(0.5)
            check("CSV export runs without a script error", not cdp.exceptions)

            await cdp.drain(0.5)
            check("no uncaught exceptions during the session", not cdp.exceptions, "; ".join(cdp.exceptions)[:300])
            check("no console errors or warnings", not cdp.console, "; ".join(cdp.console)[:300])
            await cdp.call("Emulation.setDeviceMetricsOverride", width=390, height=844, deviceScaleFactor=2, mobile=True)
            await asyncio.sleep(0.3)
            check("narrow viewport: body does not scroll horizontally", await cdp.js("document.documentElement.scrollWidth <= document.documentElement.clientWidth + 1"),
                  f"scrollWidth={await cdp.js('document.documentElement.scrollWidth')} client={await cdp.js('document.documentElement.clientWidth')}")
    finally:
        proc.terminate()
        try: proc.wait(timeout=5)
        except Exception: proc.kill()
    failed = [r for r in results if not r[1]]
    print(f"\n{len(results) - len(failed)} passed, {len(failed)} failed")
    sys.exit(1 if failed else 0)

asyncio.run(main())
