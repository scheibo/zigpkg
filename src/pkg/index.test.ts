import {compute} from '.';

describe('zigpkg', () => {
  test('compute', () => {
    expect(compute(6)).toBe(8);
    expect(() => compute(0xFFFFFFFF)).toThrow("Result overflowed");
  });
});
