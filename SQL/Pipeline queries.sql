CREATE TABLE public.bc_stage (
  "Port Name"  TEXT,
  "State"      TEXT,
  "Port Code"  INT,
  "Border"     TEXT,
  "Date"       TEXT,    -- luego la convertimos
  "Measure"    TEXT,
  "Value"      BIGINT,
  "Latitude"   TEXT,    -- a veces vienen vacíos -> los casteamos luego
  "Longitude"  TEXT,
  "Point"      TEXT     -- WKT: POINT(lon lat) (no la usaremos ahora)
);
CREATE TABLE public.border_crossings (
  port_code   INT NOT NULL,
  port_name   TEXT NOT NULL,
  state       TEXT NOT NULL,
  border      TEXT NOT NULL,      -- 'US-Canada Border' | 'US-Mexico Border'
  date        DATE NOT NULL,      -- primer día del mes
  measure     TEXT NOT NULL,
  value       BIGINT NOT NULL,
  latitude    NUMERIC(9,6),
  longitude   NUMERIC(9,6),
  CONSTRAINT pk_bc PRIMARY KEY (port_code, date, measure)
);
INSERT INTO public.border_crossings
(port_code, port_name, state, border, date, measure, value, latitude, longitude)
SELECT
  "Port Code",
  "Port Name",
  "State",
  "Border",
  to_date("Date", 'YYYY-MM-DD')::date,
  "Measure",
  "Value",
  NULLIF("Latitude",'')::numeric,
  NULLIF("Longitude",'')::numeric
FROM public.bc_stage;

-- ¿Cuántas combinaciones están duplicadas?
SELECT "Port Code"::int AS port_code,
       to_date("Date",'YYYY-MM-DD')::date AS date,
       trim("Measure") AS measure,
       COUNT(*) AS cnt,
       array_agg("Value") AS values_found
FROM public.bc_stage
GROUP BY 1,2,3
HAVING COUNT(*) > 1
ORDER BY cnt DESC;

SELECT *
FROM public.bc_stage
WHERE "Port Code" = 2606
  AND "Date" = '2021-02-01'
  AND trim("Measure") = 'Bus Passengers';

  WITH cleaned AS (
  SELECT
    "Port Code"::int                   AS port_code,
    MIN("Port Name")                   AS port_name,
    MIN("State")                       AS state,
    MIN("Border")                      AS border,
    to_date("Date",'YYYY-MM-DD')::date AS date,
    trim("Measure")                    AS measure,
    -- preferimos el no-cero; equivalente a MAX en este caso
    MAX("Value")::bigint               AS value,
    CAST(NULLIF(MIN("Latitude"),  '' ) AS numeric(9,6)) AS latitude,
    CAST(NULLIF(MIN("Longitude"), '' ) AS numeric(9,6)) AS longitude
  FROM public.bc_stage
  GROUP BY 1,5,6
)
INSERT INTO public.border_crossings
  (port_code, port_name, state, border, date, measure, value, latitude, longitude)
SELECT port_code, port_name, state, border, date, measure, value, latitude, longitude
FROM cleaned
ON CONFLICT (port_code, date, measure) DO UPDATE
SET value     = EXCLUDED.value,
    port_name = EXCLUDED.port_name,
    state     = EXCLUDED.state,
    border    = EXCLUDED.border,
    latitude  = COALESCE(EXCLUDED.latitude,  border_crossings.latitude),
    longitude = COALESCE(EXCLUDED.longitude, border_crossings.longitude);

CREATE INDEX idx_bc_date          ON public.border_crossings (date);
CREATE INDEX idx_bc_border_date   ON public.border_crossings (border, date);
CREATE INDEX idx_bc_state_measure ON public.border_crossings (state, measure, date);
CREATE INDEX idx_bc_portcode_date ON public.border_crossings (port_code, date);



-- ========== DIMENSIONES ==========
CREATE TABLE IF NOT EXISTS dim_port (
  port_key   SERIAL PRIMARY KEY,
  port_code  INT UNIQUE NOT NULL,
  port_name  TEXT NOT NULL,
  state      TEXT NOT NULL,
  border     TEXT NOT NULL,         -- 'US-Canada Border' | 'US-Mexico Border'
  latitude   NUMERIC(9,6),
  longitude  NUMERIC(9,6)
);

CREATE TABLE IF NOT EXISTS dim_date (
  date_key   SERIAL PRIMARY KEY,
  "date"     DATE NOT NULL,         -- primer día del mes
  year       INT  NOT NULL,
  quarter    INT  NOT NULL,
  month      INT  NOT NULL,
  UNIQUE ("date")
);

CREATE TABLE IF NOT EXISTS dim_measure (
  measure_key  SERIAL PRIMARY KEY,
  measure      TEXT UNIQUE NOT NULL
);

-- ========== HECHOS ==========
CREATE TABLE IF NOT EXISTS fact_crossings (
  port_key     INT NOT NULL REFERENCES dim_port(port_key),
  date_key     INT NOT NULL REFERENCES dim_date(date_key),
  measure_key  INT NOT NULL REFERENCES dim_measure(measure_key),
  value        BIGINT NOT NULL,
  PRIMARY KEY (port_key, date_key, measure_key)
);



