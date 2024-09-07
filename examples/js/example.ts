import * as zigpkg from 'zigpkg';

const arg = 'process' in globalThis && !isNaN(+process.argv[2]) ? +process.argv[2] : 42;

zigpkg.initialize()
  .then(() => console.log(zigpkg.compute(arg)))
  .catch((err: unknown) => {
    console.error(err);
    if ('process' in globalThis) process.exit(1);
  });
