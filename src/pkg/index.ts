type AddOn = {compute(this: void, n: number): number};
let ADDON: AddOn | undefined = undefined;
try {
  const src = /src[/\\]pkg$/.test(__dirname);
  ADDON = require(src ? `../../build/lib/zigpkg.node` : `../lib/zigpkg.node`) as AddOn;
} catch {
  throw new Error('Native addon not found - did you run `npm exec install-zigpkg`?');
}

export function compute(n: number) {
  return ADDON!.compute(n);
}
