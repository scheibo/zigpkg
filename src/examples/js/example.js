const zigpkg = require('zigpkg');

zigpkg.initialize();

console.log(zigpkg.add(+process.argv[2], !!process.argv[3]));
