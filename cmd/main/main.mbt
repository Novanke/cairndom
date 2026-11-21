///|
suberror CommandError {
  CommandError(String, String)
}

///|
#external
priv type IoResult

///|
extern "js" fn IoResult::error(self : Self) -> String =
  #| result => result.error || ''

///|
extern "js" fn IoResult::text(self : Self) -> String =
  #| result => result.text || ''

///|
extern "js" fn raw_arguments() -> FixedArray[String] =
  #| () => process.argv.slice(2)

///|
extern "js" fn set_exit_code(code : Int32) -> Unit =
  #| code => { process.exitCode = code; }

///|
extern "js" fn utf8_byte_length(text : String) -> Int32 =
  #| text => process.getBuiltinModule('node:buffer').Buffer.byteLength(text, 'utf8')

///|
extern "js" fn write_stderr(text : String) -> Unit =
  #| text => {
  #|   try {
  #|     const fs = process.getBuiltinModule('node:fs');
  #|     const bytes = new TextEncoder().encode(text);
  #|     let used = 0;
  #|     while (used < bytes.length) {
  #|       const count = fs.writeSync(2, bytes, used, bytes.length - used);
  #|       if (count <= 0) return;
  #|       used += count;
  #|     }
  #|   } catch {}
  #| }

///|
// The bridge adapts local files and stdout. Parsing and analysis stay in MoonBit.
extern "js" fn file_io(
  operation : String,
  input : String,
  text : String,
  stdout_error : (String) -> Unit,
) -> IoResult =
  #| (operation, input, text, stdoutError) => {
  #|   let fs, path, fd, stage, stageId, dataPath, dataId;
  #|   let parent, parentFd, parentId;
  #|   const durable = operation === 'write-durable';
  #|   const receipt = durable ? {
  #|     error:'', syncError:'', cleanupError:'', outputPath:'', stagePath:'',
  #|     published:false, directorySynced:false, stageCreated:false, stageCleaned:false,
  #|   } : null;
  #|   const identity = s => `${process.platform === 'win32' ? 'win' : s.dev}:${s.ino}:${s.birthtimeNs}`;
  #|   const stamp = (s, device = s.dev) => `${device}:${s.ino}:${s.size}:${s.mtimeNs}:${s.ctimeNs}`;
  #|   const closeOwned = () => {
  #|     const owned = fd;
  #|     fd = undefined;
  #|     fs.closeSync(owned);
  #|   };
  #|   const checkLinks = (target, missingFinal = false) => {
  #|     let cursor = path.parse(target).root;
  #|     if (fs.lstatSync(cursor).isSymbolicLink()) throw Error('symbolic links are unsupported');
  #|     const parts = target.slice(cursor.length).split(path.sep).filter(Boolean);
  #|     for (let i = 0; i < parts.length; i++) {
  #|       cursor = path.join(cursor, parts[i]);
  #|       let observed;
  #|       try { observed = fs.lstatSync(cursor); }
  #|       catch (error) {
  #|         if (missingFinal && i === parts.length - 1 && error.code === 'ENOENT') return;
  #|         throw error;
  #|       }
  #|       if (observed.isSymbolicLink()) throw Error('symbolic links are unsupported');
  #|     }
  #|   };
  #|   const directoryIdentity = s => s.isDirectory() ? String(s.dev) + ':' + String(s.ino) : null;
  #|   const checkParent = () => {
  #|     checkLinks(parent);
  #|     if (directoryIdentity(fs.lstatSync(parent, {bigint:true})) !== parentId) {
  #|       throw Error('output directory identity changed');
  #|     }
  #|   };
  #|   try {
  #|     fs = process.getBuiltinModule('node:fs');
  #|     if (operation === 'stdout') {
  #|       const output = process.stdout;
  #|       let reported = false;
  #|       const fail = error => {
  #|         if (reported) return;
  #|         reported = true;
  #|         stdoutError(String(error.message || error));
  #|       };
  #|       const onError = error => fail(error);
  #|       output.once('error', onError);
  #|       try {
  #|         // A false result is backpressure: the stream retains the queued text.
  #|         output.write(text, error => {
  #|           // An error callback precedes the error event; keep its listener.
  #|           if (error) fail(error);
  #|           else output.removeListener('error', onError);
  #|         });
  #|       } catch (error) { fail(error); }
  #|       return {error:''};
  #|     }
  #|     path = process.getBuiltinModule('node:path');
  #|     const target = path.resolve(input);
  #|     if (receipt) receipt.outputPath = target;
  #|     checkLinks(target, operation === 'write' || durable);
  #|     if (operation === 'inspect-stages') {
  #|       const stat = file => fs.lstatSync(file, {bigint:true});
  #|       const root = stat(target);
  #|       if (!root.isDirectory()) throw Error('inspection input must be a directory');
  #|       const observe = name => {
  #|         const candidate = path.join(target, name);
  #|         try {
  #|           const before = stat(candidate);
  #|           if (before.isSymbolicLink()) return 'symbolic_link';
  #|           if (!before.isDirectory()) return 'not_directory';
  #|           const contents = fs.opendirSync(candidate, {bufferSize:2});
  #|           let first, second;
  #|           try {
  #|             first = contents.readSync();
  #|             second = first && contents.readSync();
  #|           } finally { contents.closeSync(); }
  #|           let observation = first ? 'unexpected_contents' : 'empty';
  #|           if (first && !second && first.name === 'data') {
  #|             const data = path.join(candidate, 'data');
  #|             const file = stat(data);
  #|             if (file.isFile()) {
  #|               const again = stat(data);
  #|               if (!again.isFile() || stamp(file) !== stamp(again) || file.nlink !== again.nlink) {
  #|                 return 'changed';
  #|               }
  #|               if (file.nlink === 1n) observation = 'data_only';
  #|               else if (file.nlink > 1n) observation = 'data_with_other_links';
  #|             }
  #|           }
  #|           const after = stat(candidate);
  #|           return after.isDirectory() && stamp(before) === stamp(after) ? observation : 'changed';
  #|         } catch (error) {
  #|           return error.code === 'ENOENT' || error.code === 'ENOTDIR' ? 'changed' : 'unreadable';
  #|         }
  #|       };
  #|       const rows = [];
  #|       const scan = fs.opendirSync(target);
  #|       try {
  #|         let count = 0;
  #|         for (let entry; (entry = scan.readSync()) !== null;) {
  #|           if (++count > 4096) throw Error('inspection directory has more than 4096 entries');
  #|           const name = entry.name;
  #|           if (/^[.]cairndom-[A-Za-z0-9]{6}$/.test(name) && name.length === 16) {
  #|             rows.push({name, observation:observe(name)});
  #|           }
  #|         }
  #|       } finally { scan.closeSync(); }
  #|       checkLinks(target);
  #|       const after = stat(target);
  #|       if (!after.isDirectory() || stamp(root) !== stamp(after)) throw Error('inspection directory changed during reading');
  #|       return {error:'', directory:target, rows};
  #|     }
  #|     if (operation === 'read') {
  #|       const declared = fs.lstatSync(target, {bigint:true});
  #|       if (!declared.isFile() || declared.size > 2097152n) {
  #|         throw Error('input must be a regular UTF-8 file of at most 2 MiB');
  #|       }
  #|       fd = fs.openSync(target, fs.constants.O_RDONLY | (fs.constants.O_NOFOLLOW || 0) |
  #|         (fs.constants.O_NONBLOCK || 0));
  #|       const before = fs.fstatSync(fd, {bigint:true});
  #|       const named = fs.lstatSync(target, {bigint:true});
  #|       if (!before.isFile() || !named.isFile() || before.size > 2097152n) {
  #|         throw Error('input must be a regular UTF-8 file of at most 2 MiB');
  #|       }
  #|       // Node 22.16 on Windows can report different path/handle device fields.
  #|       const expected = stamp(declared);
  #|       const descriptorStamp = s => process.platform === 'win32' ? stamp(s, declared.dev) : stamp(s);
  #|       if (stamp(named) !== expected || descriptorStamp(before) !== expected) throw Error('input changed before reading');
  #|       const bytes = new Uint8Array(Number(before.size));
  #|       let used = 0;
  #|       while (used < bytes.length) {
  #|         const count = fs.readSync(fd, bytes, used, bytes.length - used, used);
  #|         if (count <= 0) throw Error('input ended during reading');
  #|         used += count;
  #|       }
  #|       if (descriptorStamp(fs.fstatSync(fd, {bigint:true})) !== expected) {
  #|         throw Error('input changed during reading');
  #|       }
  #|       const after = fs.lstatSync(target, {bigint:true});
  #|       if (!after.isFile() || stamp(after) !== expected) throw Error('input path changed during reading');
  #|       closeOwned();
  #|       return {error:'', text:new TextDecoder('utf-8', {fatal:true}).decode(bytes)};
  #|     }
  #|     if (operation !== 'write' && !durable) throw Error('unknown file operation');
  #|     const bytes = new TextEncoder().encode(text);
  #|     if (bytes.length > 16777216) throw Error('output exceeds 16 MiB');
  #|     try {
  #|       fs.lstatSync(target);
  #|       throw Error('output already exists');
  #|     } catch (error) {
  #|       if (error.code !== 'ENOENT') throw error;
  #|     }
  #|     parent = path.dirname(target);
  #|     if (receipt) {
  #|       if (process.platform === 'win32') {
  #|         receipt.syncError = 'durable directory sync is unavailable on Windows';
  #|         return receipt;
  #|       }
  #|       try {
  #|         parentId = directoryIdentity(fs.lstatSync(parent, {bigint:true}));
  #|         if (parentId === null) throw Error('output parent is not a directory');
  #|         const {O_RDONLY, O_DIRECTORY, O_NOFOLLOW, O_NONBLOCK} = fs.constants;
  #|         parentFd = fs.openSync(parent, O_RDONLY | (O_DIRECTORY || 0) |
  #|           (O_NOFOLLOW || 0) | (O_NONBLOCK || 0));
  #|         if (directoryIdentity(fs.fstatSync(parentFd, {bigint:true})) !== parentId) {
  #|           throw Error('output directory identity changed');
  #|         }
  #|         checkParent();
  #|       } catch (error) {
  #|         receipt.syncError = String(error.message || error);
  #|         return receipt;
  #|       }
  #|     }
  #|     stage = fs.mkdtempSync(path.join(parent, '.cairndom-'));
  #|     if (receipt) {
  #|       receipt.stageCreated = true;
  #|       receipt.stagePath = stage;
  #|     }
  #|     stageId = identity(fs.lstatSync(stage, {bigint:true}));
  #|     dataPath = path.join(stage, 'data');
  #|     fd = fs.openSync(dataPath, 'wx', 0o644);
  #|     dataId = identity(fs.fstatSync(fd, {bigint:true}));
  #|     let used = 0;
  #|     while (used < bytes.length) {
  #|       const count = fs.writeSync(fd, bytes, used, bytes.length - used);
  #|       if (count <= 0) throw Error('output write did not make progress');
  #|       used += count;
  #|     }
  #|     fs.fsyncSync(fd);
  #|     closeOwned();
  #|     checkLinks(stage);
  #|     if (identity(fs.lstatSync(stage, {bigint:true})) !== stageId ||
  #|         identity(fs.lstatSync(dataPath, {bigint:true})) !== dataId) {
  #|       throw Error('output stage changed');
  #|     }
  #|     if (receipt) checkParent();
  #|     fs.linkSync(dataPath, target);
  #|     if (receipt) receipt.published = true;
  #|     return receipt || {error:''};
  #|   } catch (error) {
  #|     const detail = String(error.message || error);
  #|     if (!receipt) return {error:detail};
  #|     receipt.error = detail;
  #|     return receipt;
  #|   } finally {
  #|     if (fd !== undefined) {
  #|       try { closeOwned(); }
  #|       catch (error) { if (receipt) receipt.cleanupError = String(error.message || error); }
  #|     }
  #|     if (stage && stageId) {
  #|       try {
  #|         if (receipt) checkParent();
  #|         checkLinks(stage);
  #|         const directory = fs.lstatSync(stage, {bigint:true});
  #|         if (directory.isDirectory() && identity(directory) === stageId) {
  #|           const names = fs.readdirSync(stage);
  #|           if (names.length === 1 && names[0] === 'data' && dataId) {
  #|             const data = fs.lstatSync(dataPath, {bigint:true});
  #|             if (data.isFile() && identity(data) === dataId) fs.unlinkSync(dataPath);
  #|           }
  #|           if (fs.readdirSync(stage).length === 0) {
  #|             fs.rmdirSync(stage);
  #|             if (receipt) receipt.stageCleaned = true;
  #|           }
  #|         }
  #|       } catch (error) {
  #|         if (receipt && !receipt.cleanupError) receipt.cleanupError = String(error.message || error);
  #|       }
  #|     }
  #|     if (receipt && stage && !receipt.stageCleaned && !receipt.cleanupError) {
  #|       receipt.cleanupError = 'output stage could not be cleaned safely';
  #|     }
  #|     if (receipt && parentFd !== undefined) {
  #|       // Sync the parent after cleanup, even if cleanup left some residue.
  #|       // The previously published target is never removed on later errors.
  #|       try {
  #|         if (receipt.published) {
  #|           checkParent();
  #|           fs.fsyncSync(parentFd);
  #|           checkParent();
  #|           receipt.directorySynced = true;
  #|         }
  #|       } catch (error) {
  #|         receipt.syncError = String(error.message || error);
  #|       } finally {
  #|         try { fs.closeSync(parentFd); }
  #|         catch (error) {
  #|           if (!receipt.syncError) receipt.syncError = String(error.message || error);
  #|         }
  #|       }
  #|     }
  #|   }
  #| }

///|
fn io(
  operation : String,
  path : String,
  text~ : String = "",
) -> String raise CommandError {
  let result = file_io(operation, path, text, detail => {
    print_error("io", detail)
  })
  if result.error() != "" {
    raise CommandError("io", result.error())
  }
  result.text()
}

///|
priv enum Selection {
  LoopHeader(String)
  ValueUse(String, String)
  ControlEdge(String, String)
}

///|
priv struct Options {
  command : String
  input : String
  format : String
  output : String?
  durable : Bool
  selection : Selection?
}

///|
fn is_selector(arg : String, flag : String) -> Bool {
  arg == flag || arg.has_prefix(flag + "=")
}

///|
// Parse both `--flag ID` and `--flag=ID`. The latter can name an ID
// that begins with two hyphens without consuming another option.
fn read_selector(
  args : Array[String],
  index : Int32,
  flag : String,
  previous : String?,
) -> (String?, Int32) raise CommandError {
  if previous is Some(_) {
    raise CommandError("usage", "duplicate " + flag)
  }
  let (name, last) = match args[index].strip_prefix(flag + "=") {
    Some(value) => (value.to_owned(), index)
    None => {
      let next = index + 1
      if next >= args.length() || args[next].has_prefix("--") {
        raise CommandError("usage", "missing value for " + flag)
      }
      (args[next], next)
    }
  }
  if name.is_empty() {
    raise CommandError("usage", "missing value for " + flag)
  }
  (Some(name), last)
}

///|
fn parse_options(args : Array[String]) -> Options raise CommandError {
  if args.is_empty() ||
    (
      args[0] != "analyze" &&
      args[0] != "plan-ssa" &&
      args[0] != "query" &&
      args[0] != "trace-values" &&
      args[0] != "trace-use" &&
      args[0] != "control-witness" &&
      args[0] != "loop-boundary"
    ) {
    raise CommandError(
      "usage", "expected analyze, plan-ssa, query or trace-values INPUT; run help for usage",
    )
  }
  let mut input : String? = None
  let mut format : String? = None
  let mut output : String? = None
  let mut durable = false
  let mut primary : String? = None
  let mut secondary : String? = None
  let (primary_flag, secondary_flag) = match args[0] {
    "loop-boundary" => ("--header", "")
    "trace-use" => ("--node", "--variable")
    "control-witness" => ("--controller", "--successor")
    _ => ("", "")
  }
  let mut literal = false
  let mut index = 1
  while index < args.length() {
    let arg = args[index]
    if !literal && arg == "--" {
      literal = true
    } else if !literal && arg == "--durable" {
      if durable {
        raise CommandError("usage", "duplicate --durable")
      }
      durable = true
    } else if !literal &&
      !primary_flag.is_empty() &&
      is_selector(arg, primary_flag) {
      let (value, last) = read_selector(args, index, primary_flag, primary)
      primary = value
      index = last
    } else if !literal &&
      !secondary_flag.is_empty() &&
      is_selector(arg, secondary_flag) {
      let (value, last) = read_selector(args, index, secondary_flag, secondary)
      secondary = value
      index = last
    } else if !literal && (arg == "--format" || arg == "--out") {
      if index + 1 >= args.length() ||
        args[index + 1].is_empty() ||
        args[index + 1].has_prefix("--") {
        raise CommandError("usage", "missing value for " + arg)
      }
      index += 1
      if arg == "--format" {
        if format is Some(_) {
          raise CommandError("usage", "duplicate --format")
        }
        if args[index] != "json" &&
          args[index] != "dot" &&
          args[index] != "json-summary" {
          raise CommandError(
            "usage", "--format must be json, json-summary or dot",
          )
        }
        format = Some(args[index])
      } else {
        if output is Some(_) {
          raise CommandError("usage", "duplicate --out")
        }
        output = Some(args[index])
      }
    } else if !literal && arg.has_prefix("--") {
      raise CommandError("usage", "unknown option " + arg)
    } else {
      if input is Some(_) || arg.is_empty() {
        raise CommandError("usage", "expected exactly one nonempty input path")
      }
      input = Some(arg)
    }
    index += 1
  }
  let input = match input {
    Some(path) => path
    None => raise CommandError("usage", "missing input path")
  }
  let selection = match (args[0], primary, secondary) {
    ("loop-boundary", Some(header), _) => Some(LoopHeader(header))
    ("trace-use", Some(node), Some(variable)) => Some(ValueUse(node, variable))
    ("control-witness", Some(controller), Some(successor)) =>
      Some(ControlEdge(controller, successor))
    (_, None, _) if !primary_flag.is_empty() =>
      raise CommandError("usage", "missing " + primary_flag)
    (_, _, None) if !secondary_flag.is_empty() =>
      raise CommandError("usage", "missing " + secondary_flag)
    _ => None
  }
  if args[0] != "analyze" && format == Some("dot") {
    raise CommandError(
      "usage", "this command produces JSON; DOT is only available for analyze",
    )
  }
  if args[0] != "analyze" && format == Some("json-summary") {
    raise CommandError("usage", "json-summary is only available for analyze")
  }
  if durable && output is None {
    raise CommandError("usage", "--durable requires --out")
  }
  {
    command: args[0],
    input,
    format: format.unwrap_or("json"),
    output,
    durable,
    selection,
  }
}

///|
fn execute(args : Array[String]) -> Unit raise {
  let options = parse_options(args)
  let input = io("read", options.input)
  let rendered = if options.selection is Some(LoopHeader(header)) {
    loop_boundary_report(@cairn.parse_graph(input), header)
  } else if options.selection is Some(ValueUse(node, variable)) {
    @cairn.trace_use_json_text(@cairn.parse_program(input), node, variable)
  } else if options.selection is Some(ControlEdge(controller, successor)) {
    control_witness_report(@cairn.parse_graph(input), controller, successor)
  } else if options.command == "query" {
    @cairn.query_json_text(input)
  } else if options.command == "plan-ssa" {
    @cairn.ssa_plan_json_text(@cairn.parse_program(input))
  } else if options.command == "trace-values" {
    @cairn.trace_values(@cairn.parse_program(input)).json_text()
  } else {
    let graph = @cairn.parse_graph(input)
    if options.format == "json-summary" {
      let saved = @cairn.prepare_analysis(graph)
      saved.summary_json_text() catch {
        @cairn.Invalid(_) =>
          raise CommandError("limit", "output exceeds 16 MiB")
      }
    } else if options.format == "dot" {
      @cairn.graph_dot(graph)
    } else {
      let saved = @cairn.prepare_analysis(graph)
      // Reserve the final LF inside the existing CLI byte limit.
      saved.json_text_limit(16_777_215) catch {
        @cairn.Invalid(_) =>
          raise CommandError("limit", "output exceeds 16 MiB")
      }
    }
  }
  let text = rendered + "\n"
  if utf8_byte_length(text) > 16777216 {
    raise CommandError("limit", "output exceeds 16 MiB")
  }
  match options.output {
    Some(path) if options.durable => write_durable_output(path, text)
    Some(path) => ignore(io("write", path, text~))
    None => ignore(io("stdout", "", text~))
  }
}

///|
fn print_error(code : String, detail : String) -> Unit {
  set_exit_code(2)
  write_stderr(
    Json::object(
      Map([("error", Json::string(code)), ("detail", Json::string(detail))]),
    ).stringify() +
    "\n",
  )
}

///|
fn run_command(args : Array[String]) -> Unit raise {
  let help = ["help", "--help", "-h"]
  if args.is_empty() ||
    (args.length() == 1 && help.contains(args[0])) ||
    (
      args.length() == 2 &&
      (
        args[0] == "analyze" ||
        args[0] == "plan-ssa" ||
        args[0] == "query" ||
        args[0] == "trace-values" ||
        args[0] == "trace-use" ||
        args[0] == "control-witness" ||
        args[0] == "loop-boundary" ||
        args[0] == "inspect-stages"
      ) &&
      help.contains(args[1])
    ) {
    ignore(
      io(
        "stdout",
        "",
        text="CairnDom — control-flow graph analysis\n" +
          "analyze INPUT [--format json|json-summary|dot] [--out NEW_FILE]\n" +
          "plan-ssa INPUT [--out NEW_FILE]\n" +
          "query INPUT [--out NEW_FILE]\n" +
          "trace-values INPUT [--out NEW_FILE]\n" +
          "trace-use INPUT --node NODE_ID --variable VARIABLE_ID [--out NEW_FILE] [--durable]\n" +
          "control-witness INPUT --controller NODE_ID --successor NODE_ID [--out NEW_FILE] [--durable]\n" +
          "loop-boundary INPUT --header NODE_ID [--out NEW_FILE] [--durable]\n" +
          "inspect-stages [--] DIRECTORY\n" +
          "help\n" +
          "JSON is the default format. Without --out, the result is written to stdout.\n" +
          "json-summary keeps node-level analysis and omits edge-witness expansion.\n" +
          "Input must be a regular UTF-8 file of at most 2 MiB. Output is limited to 16 MiB.\n" +
          "--out publishes a new file through staged hard-link creation; its parent must exist.\n" +
          "--durable requires --out, syncs the parent directory when supported and reports status as JSON.\n" +
          "Phi reports contain locations only; callers provide entry values and any IR rewriting.\n" +
          "Value origins describe possible last definitions and caller-supplied incoming values.\n" +
          "Node.js 22.16+ is required. Exit 0 means analysis produced; exit 2 means input or I/O error.\n",
      ),
    )
  } else if args[0] == "inspect-stages" {
    inspect_stages_command(args)
  } else {
    execute(args)
  }
}

///|
fn main {
  run_command(raw_arguments()[:].to_owned()) catch {
    CommandError(code, detail) => print_error(code, detail)
    @cairn.Invalid(detail) => print_error("input", detail)
    _ => print_error("internal", "unexpected execution error")
  }
}
