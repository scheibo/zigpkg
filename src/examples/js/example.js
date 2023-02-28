const zigpkg = require('zigpkg');

zigpkg.initialize()
  .then(() => console.log(zigpkg.compute(+process.argv[2] || 40)))
  .catch(err => {
    console.error(err);
    process.exit(1);
  });
