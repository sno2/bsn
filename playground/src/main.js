import "./index.css";
import { init, WASI } from "@wasmer/wasi";
import * as monaco from "monaco-editor";
import krTheme from "monaco-themes/themes/Sunburst.json";
import { Terminal } from "xterm";
import "xterm/css/xterm.css";

monaco.editor.defineTheme("krTheme", krTheme);

monaco.languages.register({
  id: "bs",
});

monaco.languages.register({
  id: "bsx",
});

/** @type {monaco.languages.LanguageConfiguration} */
const bsConfiguration = {
  wordPattern: /[A-Za-z_][A-Za-z_0-9]*/,
  comments: {},
  brackets: [
    ["{", "}"],
    ["(", ")"],
  ],
  autoClosingPairs: [
    { open: "{", close: "}", notIn: ["string"] },
    { open: "(", close: ")", notIn: ["string"] },
    { open: '"', close: '"', notIn: ["string"] },
  ],
  surroundingPairs: [
    { open: "{", close: "}" },
    { open: "(", close: ")" },
    { open: '"', close: '"' },
  ],
};

/** @type {monaco.languages.IMonarchLanguage} */
const bsLanguage = {
  defaultToken: "",
  tokenPostfix: ".bs",
  keywords: ["if", "else", "for", "fn", "let", "const", "try", "catch"],
  types: ["number", "object", "string"],
  constants: ["true", "false", "null"],
  ident: /[A-Za-z_][A-Za-z_0-9]*/,
  brackets: [
    { open: "{", close: "}", token: "delimiter.bracket" },
    { open: "(", close: ")", token: "delimiter.parenthesis" },
  ],
  operators: [
    "+",
    "-",
    "*",
    "/",
    "%",
    "=",
    "==",
    "!=",
    "<",
    ">",
    "<=",
    ">=",
    "&&",
    "|",
    ";",
    ".",
  ],
  symbols: /[\+\-\*\/\%\=\!\<\>\&\|\;\.]+/,
  tokenizer: {
    root: [
      // Operators
      [
        /@symbols/,
        {
          cases: {
            "@operators": "delimiter",
            "@default": "",
          },
        },
      ],

      // Strings
      ['"', "string", "@string"],

      // Call Identifiers
      [
        /@ident(?=\s*\()/,
        {
          cases: {
            "@keywords": "keyword",
            "@default": "variable.function",
          },
        },
      ],

      // Identifiers
      [
        /@ident/,
        {
          cases: {
            "@types": "type",
            "@keywords": "keyword",
            "@constants": "variable",
            "@default": "identifier",
          },
        },
      ],

      // Numbers
      [/-?[0-9]+.[0-9]*/, "number"],
      [/-?[0-9]*.[0-9]+/, "number"],
      [/-?[0-9]+/, "number"],
    ],

    string: [
      [/[^"]+/, "string"],
      [/"/, "string", "@pop"],
    ],
  },
};

monaco.languages.setLanguageConfiguration("bs", bsConfiguration);
monaco.languages.setMonarchTokensProvider("bs", bsLanguage);

const editor = monaco.editor.create(document.getElementById("container"), {
  value: "for (let i = 0; i < 10; i = i + 1) {\n  println(i)\n}\n",
  language: "bs",
  fontFamily: "Cascadia Code",
  fontSize: 17,
  theme: "krTheme",
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
      args: ["--inline-bs", code],
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
