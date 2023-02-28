import * as zigpkg from '.';

describe('zigpkg', () => {
  for (const addon of [undefined, 'node', 'wasm'] as const) {
    describe(addon || 'fallback', () => {
      beforeEach(() => zigpkg.initialize(addon));
      afterEach(zigpkg.deinitialize);
      test('compute', () => {
        expect(zigpkg.compute(6)).toBe(8);
        expect(() => zigpkg.compute(0xFFFFFFFF)).toThrow('Result overflow');
        // The addon can't distinguish input that is too large so this ends up the same
        // as above. One could choose to always use c.napi_get_value_double and then handle
        // casting internally if we can't safely assume the client will obey the API
        expect(() => zigpkg.compute(Number.MAX_SAFE_INTEGER)).toThrow('Result overflow');
      });
    });
  }
});
