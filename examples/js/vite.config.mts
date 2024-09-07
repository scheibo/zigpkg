import commonjs from 'vite-plugin-commonjs'

export default {
  publicDir: 'node_modules/zigpkg/build/lib',
  plugins: [commonjs()]
}