let NATIVE: undefined | {
  add?(this: void, n: number): number;
  addFoo?(this: void, n: number): number
} = undefined;

const SRC = /src[/\\]pkg$/;
const tryRequire = (path: string) => {
  try {
    // eslint-disable-next-line @typescript-eslint/no-var-requires
    return require(SRC.test(__dirname) ? `../../build/${path}` : `../${path}`) as typeof NATIVE;
  } catch {
    return undefined;
  }
};

const ensureInitialized = () => {
  if (!NATIVE) throw new Error('You need to call and wait for initialize before calling this');
};

export function initialize() {
  if (NATIVE) throw new Error('Cannot call initialize more than once');
  NATIVE = {
    add: tryRequire('lib/zigpkg.node')?.add,
    addFoo: tryRequire('lib/zigpkg-foo.node')?.add,
  };
  if (!NATIVE.add && !NATIVE.addFoo) {
    throw new Error('No native addons found - did you run `npm exec install-zigpkg`?');
  }
}

export function add(n: number, foo?: boolean) {
  ensureInitialized();
  if (foo) {
    if (!NATIVE?.addFoo) throw new Error('Missing native foo compatible add extension');
    return NATIVE.addFoo(n);
  } else {
    if (!NATIVE?.add) throw new Error('Missing native add extension');
    return NATIVE.add(n);
  }
}
