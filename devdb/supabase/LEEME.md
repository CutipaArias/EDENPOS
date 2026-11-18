# Réplica de EdenPOS en Supabase

MariaDB (XAMPP) sigue siendo la base principal. EdenPOS sube en segundo plano solo las filas
que cambian a una base PostgreSQL de Supabase, y esa copia sirve para restaurar en una PC nueva.

## Pasos (una sola vez)

1. Entre a https://supabase.com, cree una cuenta y pulse **New project**. Elija un nombre
   (por ejemplo `edenpos`), una región cercana (South America - São Paulo) y una contraseña
   de base de datos (guárdela; no es la de la réplica).
2. Cuando el proyecto esté listo, abra **SQL Editor > New query**.
3. Abra `01_esquema_replica.sql`, copie todo su contenido y péguelo. Busque la línea
   `v_password text := 'CAMBIE_ESTA_CONTRASEÑA';` y escriba entre las comillas una contraseña
   propia para el rol `edenpos_replica` (larga, sin comillas simples). Pulse **Run**.
   - El resultado final debe listar 17 tablas con `rls_activo = true`.
   - Si lo vuelve a ejecutar no pasa nada: no borra datos ni cambia la contraseña.
   - Para cambiarla después: `ALTER ROLE edenpos_replica WITH PASSWORD 'nueva';`
   - La contraseña queda escrita en el **historial del SQL Editor** de Supabase. Cuando termine,
     abra el historial (pestaña **History** o **Queries**) y borre esa consulta, o cambie la contraseña
     con el `ALTER ROLE` de arriba (ejecutándolo sin guardarlo) y use la nueva en EdenPOS.
   - El script también limita el rol a 5 conexiones simultáneas y 60 s por consulta.
4. Pulse **Connect** (arriba en el panel del proyecto) y, en **Session pooler**, copie:
   - **Host**: algo como `aws-0-sa-east-1.pooler.supabase.com` (o `aws-1-...`; use el que muestre su panel).
   - **Puerto**: `5432` (modo Session).
   - **Referencia del proyecto** (`<ref>`): la parte final del usuario que muestra esa pantalla
     (`postgres.<ref>`); también está en Project Settings > General.
5. En EdenPOS abra **Configuración → Réplica en Supabase** (solo la dueña) y complete la tarjeta **Conexión**:
   - **Host (Session pooler)**: el host del paso 4
   - **Puerto**: 5432
   - **Base de datos**: `postgres`
   - **Usuario**: **`edenpos_replica.<ref>`** (el usuario, un punto y la referencia del proyecto)
   - **Contraseña**: la que eligió en el paso 3 (una vez guardada, el campo queda vacío y dice
     "Guardada · deje vacío para conservarla")
   - **Certificado CA**: ya apunta al del programa (`Assets\supabase-ca.crt`); use **Elegir…** solo si necesita otro
6. Pulse **Probar conexión**: debe decir "Conexión correcta con Supabase".
7. Marque **Activar réplica en esta PC** (solo en la PC que tiene la base principal) y pulse **Guardar**.
   La tarjeta **Estado** pasa a "Esperando" y en un par de minutos a "Al día". **Subir ahora** fuerza una subida.
8. Para recuperar los datos en una PC nueva: configure la conexión y use la tarjeta
   **Restaurar desde Supabase** (pide dos confirmaciones y guarda antes una copia local automática).

## Réplica "Bloqueada" y `02_vaciar_replica.sql`

EdenPOS se niega a subir cuando la réplica ya contiene datos de otra base (otra instalación o una
base distinta) y lo muestra como **Bloqueada**. Si usted sabe que esos datos sobran y quiere empezar de cero:

1. Confirme que la base principal de esta PC (MariaDB) es la correcta. Si la copia de Supabase es la buena,
   no siga: use **Restaurar desde Supabase**.
2. En **SQL Editor** ejecute `02_vaciar_replica.sql`. **Borra todas las filas de la réplica** (las 16 tablas
   y `_replica_info`); no toca MariaDB ni la estructura.
3. En EdenPOS pulse **Subir ahora**: la réplica se vuelve a llenar con los datos de esta PC.

## Por qué el usuario lleva `.<ref>`

El Session pooler de Supabase (Supavisor) usa un único host por región para muchos proyectos,
así que identifica el proyecto por el sufijo del usuario: `usuario.<ref>`. Con el usuario
`edenpos_replica` a secas el pooler responde "Tenant or user not found". La conexión directa
(`db.<ref>.supabase.co`) usa el usuario sin sufijo, pero muchas redes solo alcanzan ese host por IPv6;
por eso se recomienda el Session pooler (IPv4).

## Seguridad

- El rol `edenpos_replica` solo tiene acceso al esquema `edenpos` (tablas con RLS y una política
  exclusiva para ese rol). `anon`, `authenticated` y `public` no tienen ningún permiso, así que la API
  pública de Supabase (REST/GraphQL) no expone nada de estas tablas, aunque alguien conozca la URL del proyecto.
- No comparta la contraseña ni la cadena de conexión. EdenPOS verifica el certificado TLS del
  servidor contra la CA de Supabase (`Assets\supabase-ca.crt`).
- **No agregue `edenpos` a "Exposed schemas"** (Project Settings > API) de Supabase. Aunque el esquema tiene
  RLS y permisos cerrados, exponerlo en la API pública es innecesario y amplía la superficie de ataque; EdenPOS
  se conecta directo a PostgreSQL y no lo necesita.
- El certificado de la CA incluido (`Assets\supabase-ca.crt`) **vence el 26/04/2031**. Antes de esa fecha
  descargue la CA vigente desde Project Settings > Database > SSL Configuration y reemplace el archivo
  (o elíjalo con **Elegir…**); si no, la conexión TLS será rechazada.
- La réplica contiene hashes de PIN y datos de clientes (DNI): trátela como información sensible.
