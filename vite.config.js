import { defineConfig, loadEnv } from 'vite'
import vue from '@vitejs/plugin-vue'
import { fileURLToPath, URL } from 'node:url'

// En desarrollo, este plugin ejecuta las funciones de /api igual que Vercel,
// así no hace falta instalar la CLI de Vercel para probar en local.
function localApi() {
  return {
    name: 'tauros-local-api',
    configureServer(server) {
      server.middlewares.use('/api', async (req, res, next) => {
        const name = (req.url || '').split('?')[0].replace(/^\/+|\/+$/g, '')
        if (!/^[a-z0-9-]+$/i.test(name)) return next()
        try {
          const mod = await server.ssrLoadModule(`/api/${name}.js`)
          await mod.default(req, res)
        } catch (err) {
          if (String(err?.message || '').includes('Failed to load')) return next()
          console.error(err)
          res.statusCode = 500
          res.end(JSON.stringify({ error: 'SERVER_ERROR' }))
        }
      })
    }
  }
}

export default defineConfig(({ mode }) => {
  // Carga también las variables sin prefijo VITE_ (solo para el servidor local de /api)
  const env = loadEnv(mode, process.cwd(), '')
  for (const [k, v] of Object.entries(env)) if (!(k in process.env)) process.env[k] = v

  return {
    plugins: [vue(), localApi()],
    resolve: { alias: { '@': fileURLToPath(new URL('./src', import.meta.url)) } }
  }
})
