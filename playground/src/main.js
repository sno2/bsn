import "./index.css";
import { init, WASI } from "@wasmer/wasi";
import * as monaco from "monaco-editor";
import Sunburst from "monaco-themes/themes/Sunburst.json";
import Dawn from "monaco-themes/themes/Dawn.json";
import { Terminal } from "xterm";
import { FitAddon } from "@xterm/addon-fit";
import "xterm/css/xterm.css";
import "./language.js";
import * as ansi from "./ansi.js";
import examples from "../data/examples.json";

const $examples = document.getElementById("examples");
const $examplesBtn = document.getElementById("examples-btn");

$examples.addEventListener("click", (e) => {
  if (e.target === $examples) {
    $examples.classList.add("hidden");
  }
});

let injectedExamples = false;
$examplesBtn.addEventListener("click", () => {
  const $content = $examples.querySelector(".content");

  if (!injectedExamples) {
    for (const example of examples) {
      const node = document.createElement("button");
      node.textContent = example.name;
      node.addEventListener("click", () => {
        const kind = example.name.endsWith(".bs") ? "bs" : "bsx";
        $examples.classList.add("hidden");
        editor.setValue(example.text);
        updateLanguage(kind);
      });
      $content.appendChild(node);
    }

    injectedExamples = true;
  }

  $examples.classList.remove("hidden");
});

monaco.editor.defineTheme("Sunburst", Sunburst);
monaco.editor.defineTheme("Dawn", Dawn);

const editor = monaco.editor.create(document.getElementById("container"), {
  value: 'waffle("Hello, world!")\n',
  language: "bsx",
  fontFamily: "consolas",
  fontSize: 17,
  theme: "Sunburst",
  tabSize: 4,
  wordWrap: "on",
});

const term = new Terminal({
  fontFamily: "consolas",
  fontSize: 17,
  theme: {
    background: "#000",
  },
});
const fitAddon = new FitAddon();
term.loadAddon(fitAddon);

term.open(document.getElementById("terminal"));
term.write(ansi.blue("$ "));

fitAddon.fit();

editor.addAction({
  id: "run",
  label: "Run Code",
  keybindings: [monaco.KeyMod.Shift | monaco.KeyCode.Enter],
  run: () => $runBtn.click(),
});

const moduleBytes = fetch("/bussin.wasm");

// TODO: We probably should await this.
init();

const wasmUtils = WebAssembly.instantiateStreaming(fetch("/wasm_utils.wasm"));
const module = WebAssembly.compileStreaming(moduleBytes);

const $runBtn = document.getElementById("run-btn");
const $bsBtn = document.getElementById("bs-btn");
const $bsxBtn = document.getElementById("bsx-btn");

const encoder = new TextEncoder();
const decoder = new TextDecoder();

const Syntax = {
  bs: 0,
  bsx: 1,
};

let currentSyntax = Syntax.bsx;

const markers = [];

editor.onDidChangeModelContent(async (e) => {
  markers.length = 0;
  console.log("here 1");

  const sourceText = editor.getValue();
  const model = editor.getModel();

  if (sourceText.length !== 0) {
    console.log("here 2");

    const lib = (await wasmUtils).instance;
    const memory = lib.exports.memory;

    const sourcePtr = lib.exports.alloc(sourceText.length);

    encoder.encodeInto(
      sourceText,
      new Uint8Array(memory.buffer, sourcePtr, sourceText.length)
    );

    console.log("here 3", performance.now());
    console.log(sourceText);
    const dataPtr = lib.exports.validate(
      currentSyntax,
      sourcePtr,
      sourceText.length
    );
    console.log("here 4", performance.now());

    if (dataPtr !== 0) {
      const errorInfo = new Uint32Array(memory.buffer, dataPtr, 4);

      const messagePtr = errorInfo[0];
      const messageLen = errorInfo[1];
      const startIndex = errorInfo[2];
      const endIndex = errorInfo[3];

      const message = decoder.decode(
        new Uint8Array(memory.buffer, messagePtr, messageLen)
      );

      const start = model.getPositionAt(startIndex);
      const end = model.getPositionAt(endIndex);

      markers[0] = {
        startLineNumber: start.lineNumber,
        endLineNumber: end.lineNumber,
        startColumn: start.column,
        endColumn: end.column,
        message,
        severity: monaco.MarkerSeverity.Error,
      };

      lib.exports.freeErrorInfo(dataPtr);
    }
  }

  monaco.editor.setModelMarkers(model, "owner", markers);
});

async function runTranslation(targetBs) {
  const lib = (await wasmUtils).instance;
  const memory = lib.exports.memory;

  const sourceText = editor.getValue();

  if (sourceText.length !== 0) {
    const sourcePtr = lib.exports.alloc(sourceText.length);

    encoder.encodeInto(
      sourceText,
      new Uint8Array(memory.buffer, sourcePtr, sourceText.length)
    );

    const status = lib.exports.translate(
      targetBs,
      sourcePtr,
      sourceText.length
    );

    if (status >= 0) {
      const translatedLength = status;

      const translatedPtr = lib.exports.getTranslatedPointer();

      const translatedBuffer = new Uint8Array(
        memory.buffer,
        translatedPtr,
        translatedLength
      );

      const translated = decoder.decode(translatedBuffer);

      editor.setValue(translated);

      lib.exports.free(translatedPtr, translatedLength);
    } else {
      console.error("Failed to translate code with error:", status);
    }

    lib.exports.free(sourcePtr, sourceText.length);
  }

  updateLanguage(targetBs ? "bs" : "bsx");
}

/** @param {"bs" | "bsx"} target */
function updateLanguage(target) {
  if (target == "bs") {
    currentSyntax = Syntax.bs;
    $bsBtn.classList.add("hidden");
    $bsxBtn.classList.remove("hidden");
    editor.updateOptions({ language: "bs", theme: "Dawn" });
    term.options.theme = { background: "#111" };
    document.body.classList.remove("dark");
  } else {
    currentSyntax = Syntax.bsx;
    $bsBtn.classList.remove("hidden");
    $bsxBtn.classList.add("hidden");
    editor.updateOptions({ language: "bsx", theme: "Sunburst" });
    term.options.theme = { background: "#000" };
    document.body.classList.add("dark");
  }
  term.reset();
  term.write(ansi.blue("$ "));
}

$bsBtn.addEventListener("click", () => runTranslation(true));
$bsxBtn.addEventListener("click", () => runTranslation(false));

$runBtn.addEventListener("click", async () => {
  let start;
  let status = 1;

  // Instantiate the WASI module
  try {
    term.reset();
    term.writeln(ansi.blue("$") + " bsn run main.bs");

    const code = editor.getValue();

    let wasi = new WASI({
      env: {
        // 'ENVVAR1': '1',
        // 'ENVVAR2': '2'
      },
      args: [
        "--inline-bs" + (document.body.classList.contains("dark") ? "x" : ""),
        code,
      ],
    });

    wasi.instantiate(await module, {
      env: {},
    });

    start = performance.now();

    // Run the start function
    status = wasi.start();

    term.write(wasi.getStdoutString().replaceAll("\n", "\n\r"));
    term.writeln(wasi.getStderrString().replaceAll("\n", "\n\r"));

    wasi.free();
  } catch (err) {
    console.error(err);
  }

  term.write(
    ansi.gray(
      `[exit status: 0, duration: ${(performance.now() - start).toFixed(2)}ms] `
    )
  );
});
