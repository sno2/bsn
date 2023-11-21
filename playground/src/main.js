import "./index.css";
import { init, WASI } from "@wasmer/wasi";
import * as monaco from "monaco-editor";
import Sunburst from "monaco-themes/themes/Sunburst.json";
import { Terminal } from "xterm";
import "xterm/css/xterm.css";
import "./language.js";

monaco.editor.defineTheme("Sunburst", Sunburst);

const editor = monaco.editor.create(document.getElementById("container"), {
  value:
    'yall (lit i be 0 rn i smol 10 rn i be i + 1) {\n  waffle("Currently at", i)\n}\n',
  language: "bsx",
  fontFamily: "consolas",
  fontSize: 17,
  theme: "Sunburst",
});

const term = new Terminal({
  fontFamily: "consolas",
  fontSize: 17,
  theme: {
    background: "#000",
  },
});
term.open(document.getElementById("terminal"));
term.write("$ ");

editor.onKeyDown((e) => {
  if (e.keyCode === monaco.KeyCode.Enter && e.shiftKey) {
    e.preventDefault();
    e.stopPropagation();

    $runBtn.click();
  }
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

async function runTranslation(targetBs) {
  const lib = (await wasmUtils).instance;
  const memory = lib.exports.memory;

  const sourceText = editor.getValue();

  const sourcePtr = lib.exports.alloc(sourceText.length);

  encoder.encodeInto(
    sourceText,
    new Uint8Array(memory.buffer, sourcePtr, sourceText.length)
  );

  const status = lib.exports.translate(targetBs, sourcePtr, sourceText.length);

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

  if (targetBs) {
    $bsBtn.classList.add("hidden");
    $bsxBtn.classList.remove("hidden");
    editor.updateOptions({ language: "bs" });
  } else {
    $bsBtn.classList.remove("hidden");
    $bsxBtn.classList.add("hidden");
    editor.updateOptions({ language: "bsx" });
  }
}

$bsBtn.addEventListener("click", () => runTranslation(true));
$bsxBtn.addEventListener("click", () => runTranslation(false));

$runBtn.addEventListener("click", async () => {
  // Instantiate the WASI module
  try {
    term.clear();
    term.writeln("$ bsn run main.bs");

    const code = editor.getValue();

    let wasi = new WASI({
      env: {
        // 'ENVVAR1': '1',
        // 'ENVVAR2': '2'
      },
      args: ["--inline-bsx", code],
    });

    wasi.instantiate(await module, {
      env: {},
    });

    const start = performance.now();

    // Run the start function
    wasi.start();

    term.write(wasi.getStdoutString().replaceAll("\n", "\n\r"));
    term.writeln(wasi.getStderrString().replaceAll("\n", "\n\r"));
    term.write(
      `[exit status: 0, duration: ${(performance.now() - start).toFixed(2)}ms] `
    );

    wasi.free();
  } catch (err) {
    console.error(err);
  }
});
