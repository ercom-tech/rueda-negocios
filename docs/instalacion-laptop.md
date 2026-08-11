# Instalación en la laptop-servidor (Ubuntu)

Guía para echar a andar `rueda-negocios` + `rueda-api` en una laptop Ubuntu
recién formateada, con la **BD del ERP en un servidor de testing** y el
**Postgres de la app local** en la laptop (modelo laptop-servidor). Instala en
modo *development* — el empaquetado de producción es la fase de deployment
pendiente.

## 0. Red y DNS

La instalación necesita internet. Si `git`/`apt` fallan con *"Temporary
failure in name resolution"* pero `ping -c2 1.1.1.1` sí responde, el DHCP de
la red no entrega DNS. Arreglo:

```bash
ip -br a                                   # identifica tu interfaz
sudo resolvectl dns <INTERFAZ> 1.1.1.1 8.8.8.8
sudo resolvectl flush-caches
# permanente:
nmcli connection show
sudo nmcli connection modify "TU_CONEXION" ipv4.dns "1.1.1.1 8.8.8.8" ipv4.ignore-auto-dns yes
sudo nmcli connection up "TU_CONEXION"
```

## 1. Paquetes del sistema

```bash
sudo apt update
sudo apt install -y git curl build-essential libssl-dev libyaml-dev \
  zlib1g-dev libffi-dev libpq-dev postgresql postgresql-contrib
```

`libpq-dev` es para la gem `pg`; `postgresql-contrib` trae `pg_trgm` (índices
de los buscadores). **Node NO se necesita** (importmap + binario de Tailwind).

## 2. Ruby 3.3.7 (rbenv)

```bash
git clone https://github.com/rbenv/rbenv.git ~/.rbenv
git clone https://github.com/rbenv/ruby-build.git ~/.rbenv/plugins/ruby-build
echo 'export PATH="$HOME/.rbenv/bin:$PATH"' >> ~/.bashrc
echo 'eval "$(rbenv init - bash)"' >> ~/.bashrc
exec $SHELL
rbenv install 3.3.7      # compila; tarda varios minutos
rbenv global 3.3.7
gem install bundler
```

## 3. Deploy keys y clonado

Deploy keys = llaves SSH de **solo lectura** por repo (revocables sin tocar
cuentas personales). GitHub solo permite cada llave en UN repo → dos llaves +
aliases SSH:

```bash
ssh-keygen -t ed25519 -C "laptop-rueda · rueda-negocios" -f ~/.ssh/deploy_rueda_negocios -N ""
ssh-keygen -t ed25519 -C "laptop-rueda · rueda-api"      -f ~/.ssh/deploy_rueda_api -N ""
```

Alta en GitHub (admin del repo): `Settings → Deploy keys → Add deploy key`,
pegar la `.pub` correspondiente, **sin** "Allow write access". Una por repo.

```bash
cat >> ~/.ssh/config <<'SSHEOF'
Host github-rueda-negocios
  HostName github.com
  User git
  IdentityFile ~/.ssh/deploy_rueda_negocios
  IdentitiesOnly yes

Host github-rueda-api
  HostName github.com
  User git
  IdentityFile ~/.ssh/deploy_rueda_api
  IdentitiesOnly yes
SSHEOF
chmod 600 ~/.ssh/config

ssh -T git@github-rueda-negocios     # → "Hi ercom-tech/rueda-negocios! ..."

mkdir -p ~/Projects/_fecego && cd ~/Projects/_fecego
git clone git@github-rueda-negocios:ercom-tech/rueda-negocios.git
git clone git@github-rueda-api:ercom-tech/rueda-api.git
```

(Las URLs usan el alias, no `github.com` — así git elige la llave correcta;
`git pull` para actualizar funciona igual.)

## 4. Postgres local (BD de la app)

```bash
sudo -u postgres psql -c "CREATE ROLE fecego LOGIN SUPERUSER PASSWORD 'fecego';"
```

El Postgres de Ubuntu escucha en el puerto **5432** (no el 1702 del entorno
Mac de desarrollo).

## 5. rueda-api → ERP de testing

```bash
cd ~/Projects/_fecego/rueda-api
bundle install
cp .env.example .env
```

`.env`:

```
APP_ENV=development
LOG_LEVEL=info
DB_HOST=<IP-DEL-SERVIDOR-DE-TESTING>
DB_PORT=5432
DB_NAME=fecego
DB_USER=<usuario>
DB_PASSWORD=<contraseña>
```

```bash
bundle exec rackup -p 4568
curl localhost:4568/health     # → {"status":"ok","db":"ok"}
curl localhost:4568/ruedas     # → ruedas del ERP
```

⚠️ El Postgres del servidor de testing debe aceptar conexiones desde la
laptop (`listen_addresses` y regla en `pg_hba.conf`).

## 6. rueda-negocios

```bash
cd ~/Projects/_fecego/rueda-negocios
bundle install
cp .env.example .env
```

`.env` (vs el ejemplo solo cambia el puerto):

```
DB_HOST=localhost
DB_PORT=5432
DB_NAME=rueda_negocios_development
DB_NAME_TEST=rueda_negocios_test
DB_USER=fecego
DB_PASSWORD=fecego
RUEDA_API_URL=http://localhost:4568
RUEDA_ID=3
```

```bash
bin/rails db:prepare        # crea BD + schema (incluye pg_trgm)
bin/rails db:seed           # usuario "servidor" (password rueda2026, o SEED_SERVER_PASSWORD)
bin/rails tailwindcss:build
```

## 7. Levantar y arranque funcional

```bash
bin/dev     # Rails en 0.0.0.0:3000 + watcher de Tailwind
```

(o `bin/rails server -b 0.0.0.0`). El bind a 0.0.0.0 permite el acceso desde
la LAN; `config.hosts` de development ya acepta IPs 192.168.x.x y 10.x.x.x.

1. `http://localhost:3000` (o `http://<IP-laptop>:3000` desde la LAN).
2. Login **servidor / rueda2026** → **Elegir rueda** → **Obtener información**.
3. Los capturistas quedan con las contraseñas que tengan **en el ERP de
   testing** (el sync trae sus digests bcrypt).

## 8. Dejarlo corriendo como servicio (systemd)

Para que el sitio arranque solo al encender la laptop y nadie tenga que abrir
una consola en el evento. **`bin/dev` no sirve aquí**: levanta además el
watcher de Tailwind, que solo hace falta al editar código; el CSS se compila al
actualizar (`bin/rails tailwindcss:build`).

`/etc/systemd/system/rueda-negocios.service` (ajusta `<usuario>`):

```ini
[Unit]
Description=rueda-negocios (Rails) - laptop servidor LAN
After=network.target postgresql.service
Wants=postgresql.service

[Service]
User=<usuario>
WorkingDirectory=/home/<usuario>/Projects/_fecego/rueda-negocios
ExecStart=/home/<usuario>/.rbenv/shims/bundle exec rails server -b 0.0.0.0 -p 3000
Restart=always
RestartSec=3

[Install]
WantedBy=multi-user.target
```

```bash
sudo systemctl daemon-reload
sudo systemctl enable --now rueda-negocios
sudo systemctl status rueda-negocios
journalctl -u rueda-negocios -f        # logs en vivo
```

En *development* la app carga su `.env` sola (dotenv-rails), así que el unit no
necesita `EnvironmentFile`. El `After=postgresql.service` espera al Postgres
local, y el barrido de corridas de sync huérfanas corre en cada arranque del
servicio: un apagón a media corrida se recupera solo.

Antes de habilitarlo, verifica que no quede un `bin/dev` corriendo
(`ss -tlnp | grep 3000`), o el servicio no podrá tomar el puerto.

**Actualizar después:** `git pull` + `bundle install` (si cambió el Gemfile) +
`bin/rails db:migrate` + `bin/rails tailwindcss:build` +
`sudo systemctl restart rueda-negocios`.

## Notas

- **La API ya no corre en la laptop.** `rueda-api` vive en el servidor de
  testing (`RUEDA_API_URL=http://fecegowstest:7011`); el paso 5 solo aplica si
  se quiere una copia local para pruebas.
- Zona horaria (`hora_pedido` usa hora local):
  `sudo timedatectl set-timezone America/Mexico_City`.
- Firewall: si `ufw` está activo, `sudo ufw allow 3000/tcp`.
- ¿BD de la app también en el servidor de testing? Cambia `DB_HOST`/`DB_PORT`
  en el `.env` de rueda-negocios (el rol necesita `CREATEDB` y `pg_trgm`
  disponible) y sáltate el paso 4.
- Para actualizar la laptop después: `git pull` en ambos repos +
  `bundle install` + `bin/rails db:migrate` + `bin/rails tailwindcss:build`.

## Equipos cliente (tablets/laptops de capturistas)

El sitio corre en HTTP plano (TLS llega hasta la fase de *strengthening*).
**Chrome sube automáticamente a HTTPS** ("Usar siempre conexiones seguras") y
muestra "site is unreachable" aunque el server esté bien (síntoma: `curl`
responde 200 pero Chrome no abre). En cada equipo cliente con Chrome:

1. `chrome://settings/security` → desactivar **"Usar siempre conexiones
   seguras"**.
2. Si insiste: `chrome://net-internals/#hsts` → *Delete domain security
   policies* con la IP de la laptop.
3. Teclear la URL con `http://` explícito: `http://<IP-laptop>:3000`.

Safari y Firefox abren HTTP de LAN sin fricción — son alternativa directa.
