import {initialize, add} from '.';

beforeAll(initialize);

describe('zigpkg', () => {
  for (const [foo, val] of [[false, 8], [true, 7]] as const) {
    test(`add (foo=${foo.toString()})`, () => {
      expect(add(6, foo)).toBe(val);
    });
  }
});
