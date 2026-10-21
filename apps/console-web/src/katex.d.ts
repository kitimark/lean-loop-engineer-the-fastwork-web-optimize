declare module "katex" {
  export interface KatexOptions { displayMode?: boolean; throwOnError?: boolean; output?: "html" | "mathml" | "htmlAndMathml"; strict?: boolean | string }
  const katex: { renderToString(tex: string, options?: KatexOptions): string };
  export default katex;
}
declare module "katex/dist/katex.min.css";
