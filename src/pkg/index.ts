import {load} from './node';

export type Argument = string | URL | WebAssembly.Module | Promise<Response>;
export type AddOn = {compute(this: void, n: number): number};

let ADDON: AddOn | undefined = undefined;
let loading: Promise<AddOn> | undefined = undefined;

export async function initialize(addon?: Argument) {
  if (loading) throw new Error('Cannot call initialize more than once');
  loading = load(addon);
  loading.then(a => {
    ADDON = a;
  }).catch(() => {
    loading = undefined;
  });
  return loading?.then(() => {});
}

export function compute(n: number) {
  if (!ADDON) throw new Error('You must call and wait for initialize before calling compute');
  return ADDON.compute(n);
}

// @test-only
export function deinitialize() {
  loading = undefined;
}