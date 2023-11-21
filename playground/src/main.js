import "./index.css";
import { init, WASI } from "@wasmer/wasi";
import * as monaco from "monaco-editor";
import Sunburst from "monaco-themes/themes/Sunburst.json";
import { Terminal } from "xterm";
import "xterm/css/xterm.css";
import "./language.js";

monaco.editor.defineTheme("Sunburst", Sunburst);

const editor = monaco.editor.create(document.getElementById("container"), {
  value: "for (let i = 0; i < 10; i = i + 1) {\n  println(i)\n}\n",
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

const module = WebAssembly.compileStreaming(moduleBytes);

const $output = document.getElementById("output");
const $runBtn = document.getElementById("run-btn");

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
