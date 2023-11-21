import * as monaco from "monaco-editor";

/**
 * @param {"bs" | "bsx"} syntax
 */
function createLanguageData(syntax) {
  /** @type {monaco.languages.LanguageConfiguration} */
  const configuration = {
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
  const language = {
    defaultToken: "",
    tokenPostfix: ".bs",
    keywords: [
      "if",
      "else",
      "for",
      "fn",
      "let",
      "const",
      "try",
      "catch",
      ...(syntax === "bsx"
        ? [
            "rn",
            "be",
            "lit",
            "mf",
            "sus",
            "fake",
            "impostor",
            "nah",
            "fr",
            "btw",
            "carenot",
            "bruh",
            "yall",
            "smol",
            "thicc",
            "fuck_around",
            "find_out",
          ]
        : []),
    ],
    types: ["number", "object", "string"],
    constants: [
      "true",
      "false",
      "null",
      ...(syntax === "bsx" ? ["fake", "nocap", "cap"] : []),
    ],
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

  return { configuration, language };
}

const bs = createLanguageData("bs");
const bsx = createLanguageData("bsx");

monaco.languages.register({ id: "bs" });
monaco.languages.setLanguageConfiguration("bs", bs.configuration);
monaco.languages.setMonarchTokensProvider("bs", bs.language);

monaco.languages.register({ id: "bsx" });
monaco.languages.setLanguageConfiguration("bsx", bsx.configuration);
monaco.languages.setMonarchTokensProvider("bsx", bsx.language);
