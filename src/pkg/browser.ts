import {AddOn, Argument, overflow} from '.';

type WASM = {instance: {exports: AddOn}};

export async function load(addon?: Argument): Promise<AddOn> {
  console.log("hello from browser");
  throw new Error();

  // if (typeof addon === 'object' || addon === 'wasm') {
  //   try {
  //     if ()      const buf = fs.readFileSync(path.join(ROOT, 'build', 'lib', 'zigpkg.wasm'));
  //     const wasm = await WebAssembly.instantiate(buf, {env: {overflow}}) as unknown as WASM;
  //     ADDON = wasm.instance.exports;
  //   } catch (err) {
  //     const message = addon ? 'Unable to find addons' : 'WASM addon not found';
  //     throw new Error(`${message} - did you run \`npx install-zigpkg\`?`);
  //   }
  // } else {
  //   try {
  //     ADDON = require(path.join(ROOT, 'build', 'lib', 'zigpkg.node')) as AddOn;
  //     return;
  //   } catch {
  //     if (addon == 'node') {
  //       throw new Error('Native addon not found - did you run `npx install-zigpkg`?');
  //     }
  //   }
  // }

}