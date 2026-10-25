// Module resolve hook: an extensionless relative import ("./logic") resolves to its ".ts" file. The production parts are
// written for the bundler (gesture.ts imports './logic'); Node strips their types but does not guess the extension.
export async function resolve(specifier, context, nextResolve) {
  try {
    return await nextResolve(specifier, context);
  } catch (e) {
    if (e && e.code === 'ERR_MODULE_NOT_FOUND' && specifier.startsWith('.') && !/\.\w+$/.test(specifier)) return nextResolve(`${specifier}.ts`, context);
    throw e;
  }
}
