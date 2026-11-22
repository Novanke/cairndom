///|
#external
priv type StageProcesses

///|
extern "js" fn StageProcesses::context(self : Self) -> String =
  #| result => result.context

///|
extern "js" fn StageProcesses::state(self : Self, pid : Int32) -> String =
  #| (result, pid) => result.states.get(pid) || ''

///|
// Probe local OS process identities. A blank token carries no evidence.
extern "js" fn stage_processes(pids : FixedArray[Int32]) -> StageProcesses =
  #| pids => {
  #|   const result = {context:'', states:new Map()};
  #|   const selected = [...new Set(pids.filter(pid => Number.isInteger(pid) && pid > 0))];
  #|   if (!selected.length || selected.length > 4096) return result;
  #|   try {
  #|     const fs = process.getBuiltinModule('node:fs');
  #|     const crypto = process.getBuiltinModule('node:crypto');
  #|     const context = parts => process.platform + ':' +
  #|       crypto.createHash('sha256').update(JSON.stringify(parts)).digest('hex');
  #|     if (process.platform === 'linux') {
  #|       const readSmall = (file, max) => {
  #|         const fd = fs.openSync(file, fs.constants.O_RDONLY |
  #|           (fs.constants.O_NONBLOCK || 0) | (fs.constants.O_NOFOLLOW || 0));
  #|         try {
  #|           const bytes = new Uint8Array(max + 1);
  #|           let used = 0;
  #|           while (used < bytes.length) {
  #|             const count = fs.readSync(fd, bytes, used, bytes.length - used, null);
  #|             if (count === 0) return new TextDecoder().decode(bytes.subarray(0, used));
  #|             used += count;
  #|           }
  #|           throw Error('excessive process metadata');
  #|         } finally { fs.closeSync(fd); }
  #|       };
  #|       if (fs.statfsSync('/proc', {bigint:true}).type !== 0x9fa0n) return result;
  #|       const boot = readSmall('/proc/sys/kernel/random/boot_id', 128).trim();
  #|       const namespace = fs.readlinkSync('/proc/self/ns/pid');
  #|       const ownStatus = readSmall('/proc/self/status', 16384);
  #|       const ownPid = /^NSpid:[\t ]+(\d+)[\t ]*$/m.exec(ownStatus);
  #|       if (!/^[0-9a-f-]{36}$/.test(boot) || !/^pid:\[\d+\]$/.test(namespace) ||
  #|           !ownPid || Number(ownPid[1]) !== process.pid) return result;
  #|       result.context = context([boot, namespace]);
  #|       for (const pid of selected) {
  #|         try {
  #|           const stat = readSmall('/proc/' + pid + '/stat', 4096);
  #|           const end = stat.lastIndexOf(')');
  #|           if (!stat.startsWith(pid + ' (') || end < 0) continue;
  #|           // The command can contain spaces and parentheses. State is
  #|           // field 3 and process start time is field 22.
  #|           const fields = stat.slice(end + 1).trim().split(/\s+/);
  #|           if (/^\d{1,20}$/.test(fields[19])) {
  #|             if (/^[ZXx]$/.test(fields[0])) result.states.set(pid, 'dead');
  #|             else if (/^[RSDTtKWPI]$/.test(fields[0])) result.states.set(pid, fields[19]);
  #|           }
  #|         } catch (error) {
  #|           if (error.code !== 'ENOENT' && error.code !== 'ESRCH') continue;
  #|           // A restricted procfs view can hide a live PID. Signal zero
  #|           // delivers no signal and only ESRCH establishes absence.
  #|           try { process.kill(pid, 0); }
  #|           catch (probe) { if (probe.code === 'ESRCH') result.states.set(pid, 'dead'); }
  #|         }
  #|       }
  #|     } else if (process.platform === 'win32') {
  #|       const path = process.getBuiltinModule('node:path');
  #|       const buffer = process.getBuiltinModule('node:buffer').Buffer;
  #|       const {spawnSync} = process.getBuiltinModule('node:child_process');
  #|       const root = process.env.SystemRoot || '';
  #|       if (!path.isAbsolute(root)) return result;
  #|       const home = path.join(root, 'System32', 'WindowsPowerShell', 'v1.0');
  #|       const script = String.raw`
  #| $ErrorActionPreference = 'Stop'
  #| [Console]::OutputEncoding = [System.Text.UTF8Encoding]::new($false)
  #| $scope = (Get-ItemProperty -LiteralPath 'Registry::HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Cryptography' -Name MachineGuid).MachineGuid
  #| $rows = @{}
  #| $requestedIds = [Console]::In.ReadToEnd() | ConvertFrom-Json
  #| foreach ($requested in $requestedIds) {
  #|   $rows[[string]$requested] = 'dead'
  #| }
  #| foreach ($task in @(Get-Process)) {
  #|   $key = [string]$task.Id
  #|   if (!$rows.ContainsKey($key)) { continue }
  #|   $rows[$key] = ''
  #|   try {
  #|     $start = $task.StartTime
  #|     if ($null -ne $start) { $rows[$key] = $start.ToFileTimeUtc().ToString() }
  #|   } catch {}
  #| }
  #| [Console]::WriteLine((@{machine=$scope; hostName=[System.Environment]::MachineName; rows=$rows} | ConvertTo-Json -Depth 3 -Compress))
  #| `;
  #|       const output = spawnSync(path.join(home, 'powershell.exe'),
  #|         ['-NoLogo', '-NoProfile', '-NonInteractive',
  #|          '-EncodedCommand', buffer.from(script, 'utf16le').toString('base64')],
  #|         {input:JSON.stringify(selected), encoding:'utf8', timeout:5000,
  #|          windowsHide:true, maxBuffer:262144, cwd:home,
  #|          env:{...process.env, PSModulePath:path.join(home, 'Modules')}});
  #|       if (output.status !== 0 || output.error || !output.stdout) return result;
  #|       const {machine, hostName, rows} = JSON.parse(output.stdout);
  #|       if (typeof machine !== 'string' || !/^[0-9a-f-]{36}$/i.test(machine) ||
  #|           typeof hostName !== 'string' || !hostName || hostName.length > 255) return result;
  #|       result.context = context([machine.toLowerCase(), hostName.toLowerCase()]);
  #|       for (const pid of selected) {
  #|         const token = rows && rows[String(pid)];
  #|         if (token === 'dead') {
  #|           try { process.kill(pid, 0); }
  #|           catch (probe) { if (probe.code === 'ESRCH') result.states.set(pid, 'dead'); }
  #|         } else if (typeof token === 'string' && /^\d{1,20}$/.test(token)) {
  #|           result.states.set(pid, token);
  #|         }
  #|       }
  #|     }
  #|   } catch {}
  #|   return result;
  #| }
