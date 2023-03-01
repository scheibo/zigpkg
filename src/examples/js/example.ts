import * as zigpkg from 'zigpkg';

zigpkg.initialize()
  .then(() => console.log(zigpkg.compute(+process.argv[2])))
  .catch((err: unknown) => {
    console.error(err);
    process.exit(1);
  });
