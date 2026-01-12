import globals from "globals";
import pluginJs from "@eslint/js";
import tseslint from "typescript-eslint";
import pluginJest from "eslint-plugin-jest";

export default tseslint.config(
  {files: ["src/bin/!(*.*)"]},
  {ignores: ["dist/", "node_modules/", "examples/zig", "build/"]},
  pluginJs.configs.recommended,
  {
    languageOptions: {
      ecmaVersion: 2020,
      globals: {
        ...globals.browser,
        ...globals.node,
        ...globals.es2015,
      },
    },
    rules: { "no-empty": ["error", { allowEmptyCatch: true }]},
  },
  {
    files: ["**/*.ts"],
    extends: [
      ...tseslint.configs.recommended,
      ...tseslint.configs.recommendedTypeChecked,
    ],
    languageOptions: {
      parserOptions: {
        project: ["./tsconfig.json", "./examples/js/tsconfig.json"],
        tsconfigRootDir: import.meta.dirname,
      },
    },
    rules: {
      "@typescript-eslint/no-non-null-assertion": "off",
      "@typescript-eslint/no-require-imports": "off",
      "@typescript-eslint/no-var-requires": "off",
    },
  },
  {
    files: ["**/*.test.ts"],
    extends: [
        pluginJest.configs["flat/recommended"],
        pluginJest.configs["flat/style"]
    ],
    rules: {"jest/valid-title": "off"},
  }
);