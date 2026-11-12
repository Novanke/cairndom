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
extern "js" fn write_stderr(text : String) -> Unit =
  #| text => { process.stderr.write(text); }

///|
// The bridge only reads/writes local files. Parsing and analysis stay in MoonBit.
extern "js" fn file_io(
  operation : String,
  input : String,
  text : String,
) -> IoResult =
  #| (operation, input, text) => {
  #|   let fs, path, fd, stage, stageId, dataPath, dataId;
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
  #|   try {
  #|     fs = process.getBuiltinModule('node:fs');
  #|     path = process.getBuiltinModule('node:path');
  #|     const target = path.resolve(input);
  #|     checkLinks(target, operation === 'write');
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
  #|       if (stamp(named) !== expected || stamp(before, declared.dev) !== expected) throw Error('input changed before reading');
  #|       const bytes = new Uint8Array(Number(before.size));
  #|       let used = 0;
  #|       while (used < bytes.length) {
  #|         const count = fs.readSync(fd, bytes, used, bytes.length - used, used);
  #|         if (count <= 0) throw Error('input ended during reading');
  #|         used += count;
  #|       }
  #|       if (stamp(fs.fstatSync(fd, {bigint:true}), declared.dev) !== expected) {
  #|         throw Error('input changed during reading');
  #|       }
  #|       const after = fs.lstatSync(target, {bigint:true});
  #|       if (!after.isFile() || stamp(after) !== expected) throw Error('input path changed during reading');
  #|       closeOwned();
  #|       return {error:'', text:new TextDecoder('utf-8', {fatal:true}).decode(bytes)};
  #|     }
  #|     if (operation !== 'write') throw Error('unknown file operation');
  #|     const bytes = new TextEncoder().encode(text);
  #|     if (bytes.length > 16777216) throw Error('output exceeds 16 MiB');
  #|     try {
  #|       fs.lstatSync(target);
  #|       throw Error('output already exists');
  #|     } catch (error) {
  #|       if (error.code !== 'ENOENT') throw error;
  #|     }
  #|     stage = fs.mkdtempSync(path.join(path.dirname(target), '.cairndom-'));
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
  #|     fs.linkSync(dataPath, target);
  #|     return {error:''};
  #|   } catch (error) {
  #|     return {error:String(error.message || error)};
  #|   } finally {
  #|     if (fd !== undefined) { try { closeOwned(); } catch {} }
  #|     if (stage && stageId) {
  #|       try {
  #|         checkLinks(stage);
  #|         const directory = fs.lstatSync(stage, {bigint:true});
  #|         if (directory.isDirectory() && identity(directory) === stageId) {
  #|           const names = fs.readdirSync(stage);
  #|           if (names.length === 1 && names[0] === 'data' && dataId) {
  #|             const data = fs.lstatSync(dataPath, {bigint:true});
  #|             if (data.isFile() && identity(data) === dataId) fs.unlinkSync(dataPath);
  #|           }
  #|           if (fs.readdirSync(stage).length === 0) fs.rmdirSync(stage);
  #|         }
  #|       } catch {}
  #|     }
  #|   }
  #| }

///|
fn io(
  operation : String,
  path : String,
  text~ : String = "",
) -> String raise CommandError {
  let result = file_io(operation, path, text)
  if result.error() != "" {
    raise CommandError("io", result.error())
  }
  result.text()
}

///|
priv struct Options {
  input : String
  format : String
  output : String?
}

///|
fn parse_options(args : Array[String]) -> Options raise CommandError {
  if args.is_empty() || args[0] != "analyze" {
    raise CommandError("usage", "expected analyze INPUT; run help for usage")
  }
  let mut input : String? = None
  let mut format : String? = None
  let mut output : String? = None
  let mut literal = false
  let mut index = 1
  while index < args.length() {
    let arg = args[index]
    if !literal && arg == "--" {
      literal = true
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
        if args[index] != "json" && args[index] != "dot" {
          raise CommandError("usage", "--format must be json or dot")
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
  { input, format: format.unwrap_or("json"), output, }
}

///|
fn execute(args : Array[String]) -> Unit raise {
  let options = parse_options(args)
  let graph = @cairn.parse_graph(io("read", options.input))
  let analysis = @cairn.analyze(graph)
  let rendered = if options.format == "dot" {
    @cairn.analysis_dot(analysis)
  } else {
    @cairn.analysis_json_text(analysis)
  }
  let text = rendered + "\n"
  if @utf8.encode(text).length() > 16777216 {
    raise CommandError("limit", "output exceeds 16 MiB")
  }
  match options.output {
    Some(path) => ignore(io("write", path, text~))
    None => println(rendered)
  }
}

///|
fn print_error(code : String, detail : String) -> Unit {
  write_stderr(
    Json::object(
      Map([("error", Json::string(code)), ("detail", Json::string(detail))]),
    ).stringify() +
    "\n",
  )
  set_exit_code(2)
}

///|
fn main {
  let args = raw_arguments()[:].to_owned()
  let help = ["help", "--help", "-h"]
  if args.is_empty() ||
    (args.length() == 1 && help.contains(args[0])) ||
    (args.length() == 2 && args[0] == "analyze" && help.contains(args[1])) {
    println(
      "CairnDom — control-flow graph analysis\n" +
      "analyze INPUT [--format json|dot] [--out NEW_FILE]\n" +
      "help\n" +
      "JSON is the default format. Without --out, the result is written to stdout.\n" +
      "Input must be a regular UTF-8 file of at most 2 MiB. Output is limited to 16 MiB.\n" +
      "--out publishes a new file through staged hard-link creation; its parent must exist.\n" +
      "Node.js 22.16+ is required. Exit 0 means analysis produced; exit 2 means input or I/O error.",
    )
  } else {
    execute(args) catch {
      CommandError(code, detail) => print_error(code, detail)
      @cairn.Invalid(detail) => print_error("input", detail)
      _ => print_error("internal", "unexpected execution error")
    }
  }
}
