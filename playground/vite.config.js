import { defineConfig } from "vite";
import nodePolyfills from "vite-plugin-node-stdlib-browser";
import { default as monacoEditorPlugin } from "vite-plugin-monaco-editor";

export default defineConfig({
  plugins: [nodePolyfills(), monacoEditorPlugin.default({})],
});
