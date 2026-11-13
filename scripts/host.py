"""Process/filesystem adapter; reference algorithms and cases live in MoonBit."""
import argparse
import json
from pathlib import Path
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]


def require(condition, message):
    if not condition:
        raise AssertionError(message)


def diagnostic(stderr):
    value = json.loads(stderr)
    require(set(value) == {"error", "detail"} and
            all(isinstance(text, str) and text for text in value.values()), "malformed JSON error")
    return value


class Reference:
    def __init__(self, node, executable):
        self.node, self.executable, self.cache = node, executable, {}

    def run(self, command, payload=None):
        body = "" if payload is None else json.dumps(payload, ensure_ascii=False, separators=(",", ":"))
        key = command, body
        if key not in self.cache:
            result = subprocess.run([self.node, str(self.executable), command],
                                    input=body.encode("utf-8"), capture_output=True, timeout=90)
            require(result.returncode == 0 and not result.stderr,
                    f"MoonBit reference failed ({command}): {result.stderr!r}")
            self.cache[key] = json.loads(result.stdout)
        return self.cache[key]


def setup(description):
    parser = argparse.ArgumentParser(description=description)
    parser.add_argument("--node", default="node")
    parser.add_argument("--cli", type=Path, default=ROOT / "_build/js/release/build/cmd/main/main.js")
    parser.add_argument("--oracle", type=Path,
                        default=ROOT / "_build/js/release/build/verification/oracle/oracle.js")
    args = parser.parse_args()
    node = shutil.which(args.node)
    require(node is not None, f"Node executable not found: {args.node}")
    cli, oracle = args.cli.resolve(), args.oracle.resolve()
    require(cli.is_file() and oracle.is_file(), "Build the JS release CLI and verification oracle first")
    return node, cli, Reference(node, oracle)


class CliChecks:
    def __init__(self, node, cli, work, reference):
        self.node, self.cli, self.work, self.reference = node, cli, work, reference
        self.calls = self.graphs = 0
        self.skips = []
        self.foreign = work / ".cairndom-foreign"
        self.foreign.mkdir()
        (self.foreign / "keep").write_text("unrelated task\n", encoding="utf-8")

    def invoke(self, arguments, *, error=False, preload=None, timeout=30):
        command = [self.node]
        if preload is not None:
            command.extend(["--import", Path(preload).resolve().as_uri()])
        command.extend([str(self.cli), *map(str, arguments)])
        try:
            result = subprocess.run(command, cwd=self.work, capture_output=True, timeout=timeout)
        except subprocess.TimeoutExpired as exc:
            raise AssertionError(f"CLI hung: {arguments}") from exc
        self.calls += 1
        require(result.returncode == (2 if error else 0),
                f"unexpected exit {result.returncode}: {arguments}; stderr={result.stderr!r}")
        if error:
            require(not result.stdout, f"error leaked stdout: {arguments}")
            diagnostic(result.stderr)
        else:
            require(not result.stderr, f"successful CLI emitted stderr: {result.stderr!r}")
        stages = {path.relative_to(self.work).as_posix() for path in self.work.rglob(".cairndom-*")}
        require(stages == {".cairndom-foreign"}, f"unexpected staging residue: {stages}")
        require((self.foreign / "keep").read_text(encoding="utf-8") == "unrelated task\n",
                "unrelated task file was changed")
        return result.stdout.decode("utf-8")

    def put_graph(self, name, value):
        path = self.work / f"{name}.json"
        path.write_text(json.dumps(value, ensure_ascii=False), encoding="utf-8")
        return path

    def check_case(self, command, name, value, expected=None):
        path = self.put_graph(name, value)
        if expected is None:
            expected = self.reference.run({"analyze": "graph", "plan-ssa": "program", "query": "query"}[command], value)
            if command == "analyze":
                expected = expected["report"]
        actual = json.loads(self.invoke([command, path]))
        require(actual == expected, f"{command} oracle mismatch: {name}")
        self.graphs += 1
        return path, expected

    def reject(self, name, payload, command="analyze"):
        path = self.work / f"invalid-{command}-{name}.json"
        if not isinstance(payload, bytes):
            payload = (payload if isinstance(payload, str) else json.dumps(payload)).encode("utf-8")
        path.write_bytes(payload)
        out = path.with_suffix(".out")
        self.invoke([command, path, "--out", out], error=True)
        require(not out.exists(), f"invalid input published an output: {name}")

    def reject_cases(self, command):
        for case in self.reference.run("query-invalid-cases" if command == "query" else "invalid-cases"):
            if case["command"] == command:
                self.reject(case["name"], case["payload"], command)

    def bad_arguments(self, command, path):
        for number, arguments in enumerate(self.reference.run("host-cases")["bad_arguments"][command]):
            arguments = [path if value == "$input" else value for value in arguments]
            before = set(self.work.iterdir())
            self.invoke([*arguments, "--out", self.work / f"bad-args-{number}.out"], error=True)
            require(set(self.work.iterdir()) == before, "invalid arguments created an output")

    def failure_preload(self, name, source):
        path = self.work / f"preload {name} 汉字.mjs"
        path.write_text("import fs from 'node:fs';\n" + source, encoding="utf-8")
        return path

    def staged_failure(self, name, kind="partial"):
        """Inject faults only into the subprocess's owned staging descriptor."""
        action = ("const write = fs.writeSync; fs.writeSync = function(fd, buffer, offset, length, ...rest) {"
                  " if (fd === owned) { write.call(this, fd, buffer, offset, Math.min(length, 7), ...rest);"
                  " throw Error('injected partial output write'); }"
                  " return write.call(this, fd, buffer, offset, length, ...rest); };"
                  if kind == "partial" else
                  "const close = fs.closeSync; fs.closeSync = function(fd) { close.call(this, fd);"
                  " if (fd === owned) { owned = undefined; throw Error('injected close failure'); } };")
        return self.failure_preload(name,
            "const open = fs.openSync; let owned; fs.openSync = function(file, flags, ...rest) {"
            " const fd = open.call(this, file, flags, ...rest);"
            " if (flags === 'wx' && String(file).endsWith('data')) owned = fd; return fd; };" + action)

    def file_contract(self, command, name, value):
        path, expected = self.check_case(command, name, value)
        original = path.read_bytes()
        stdout = self.invoke([command, path])
        out = self.work / f"published {command} 汉字.json"
        require(self.invoke([command, path, "--out", out]) == "", "--out also wrote stdout")
        require(out.read_bytes() == stdout.encode("utf-8"), "file bytes differ from stdout")
        require(self.invoke([command, path, "--format", "json"]) == stdout, "explicit JSON format changed")
        self.invoke([command, path, "--out", out], error=True)
        require(out.read_bytes() == stdout.encode("utf-8"), "existing output was overwritten")
        self.invoke([command, path, "--out", path], error=True)
        require(path.read_bytes() == original, "input was overwritten")
        missing = self.work / "no-parent" / "report.json"
        self.invoke([command, path, "--out", missing], error=True)
        require(not missing.exists(), "missing-parent error published output")
        self.invoke([command, path, "--out", self.foreign], error=True)
        self.invoke([command, self.work / "absent.json"], error=True)
        self.invoke([command, self.work], error=True)
        literal = self.work / f"--{command}.json"
        literal.write_bytes(original)
        require(json.loads(self.invoke([command, "--", literal.name])) == expected, "literal filename failed")
        require(command + " INPUT" in self.invoke(["--help"]), "command help is unavailable")
        self.bad_arguments(command, path)
        self.reject_cases(command)
        self.reject("utf8", b"\xff\xfe", command)
        partial = self.staged_failure(command + "-partial")
        failed = self.work / "incomplete.json"
        self.invoke([command, path, "--out", failed], error=True, preload=partial)
        require(not failed.exists(), "partial write published incomplete report")
        require(path.read_bytes() == original and out.read_bytes() == stdout.encode("utf-8"),
                "failure checks changed an input or successful report")
        return path, out, original, stdout


def run_checks(description, label, verify):
    node, cli, reference = setup(description)
    with tempfile.TemporaryDirectory(prefix="cairndom-" + label.lower() + "-") as directory:
        checks = CliChecks(node, cli, Path(directory), reference)
        verify(checks)
        print(f"{label} verification passed: {checks.graphs} oracle cases, {checks.calls} real CLI invocations.")
        for skipped in checks.skips:
            print(f"SKIP: {skipped}")
