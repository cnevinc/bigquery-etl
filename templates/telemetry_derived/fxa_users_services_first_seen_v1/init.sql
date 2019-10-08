CREATE OR REPLACE TABLE
  `moz-fx-data-shared-prod.telemetry_derived.fxa_users_services_first_seen_v1`
PARTITION BY DATE(first_service_timestamp)
CLUSTER BY service, user_id AS
WITH
  -- use a window function to look within each USER and SERVICE for the first value of service, os, and country.
  -- also, get the first value of flow_id for later use and create a boolean column that is true if the first instance of a service usage includes a registration.
  first_services AS (
  SELECT
    ROW_NUMBER() OVER (w1) AS _n,
    user_id,
    service,
    udf_mode_last(ARRAY_AGG(`timestamp`) OVER (w1)) AS first_service_timestamp,
    udf_mode_last(ARRAY_AGG(os_name) OVER (w1)) AS first_service_os,
    udf_mode_last(ARRAY_AGG(country) OVER (w1)) AS first_service_country,
    udf_mode_last(ARRAY_AGG(flow_id) OVER (w1)) AS first_service_flow,
    LOGICAL_OR(
      IFNULL(event_type = 'fxa_reg - complete', FALSE)
      ) OVER (w1) AS did_register
  FROM
    `moz-fx-data-derived-datasets.telemetry.fxa_content_auth_oauth_events_v1`
  WHERE
    ((event_type IN ('fxa_login - complete', 'fxa_reg - complete'))
      OR (event_type LIKE 'fxa_activity%'))
    AND DATE(`timestamp`) >= '2019-03-01'
    AND service IS NOT NULL
    AND user_id IS NOT NULL
  WINDOW
    w1 AS (
      PARTITION BY
        user_id,
        service
      ORDER BY
        `timestamp` ) ),
  -- we need this next section because `did_register` will be BOTH true and false within the flows that the user registered on.
  -- this dedupes the rows from above and sets did_register to true only on flows that included a registration
  -- I've verified that `date(first_service_timestamp), count(distinct user_id) where did_register = true group by 1`  matches the counts of registrations per day in amplitude.
  first_services_g AS (
  SELECT
    * EXCEPT(_n)
  FROM
    first_services
  WHERE
    _n = 1),
  -- sadly, `entrypoint` is null on registration complete and login complete events.
  -- this means we have to use first_service_flow to join back on the original source table's flow_id,
  -- and take the first occurrence of `entrypoint` within the flow that the user first appeared in the service on.
  flows AS (
  SELECT
    DISTINCT s.first_service_flow,
    FIRST_VALUE(f.entrypoint) OVER (PARTITION BY f.flow_id ORDER BY f.`timestamp`) AS first_service_entrypoint
  FROM
    first_services_g s
  INNER JOIN
    `moz-fx-data-derived-datasets.telemetry.fxa_content_auth_oauth_events_v1` AS f
  ON
    s.first_service_flow = f.flow_id
  WHERE
    f.entrypoint IS NOT NULL
    AND s.first_service_flow IS NOT NULL
    AND DATE(f.`timestamp`) >= '2019-03-01'
    )
  -- finally take the entrypoint data and join it back on the other information (os, country etc).
  -- also, add a row number that indicates the order in which the user signed up for their services.
SELECT
  s.*,
  f.first_service_entrypoint AS entrypoint,
  ROW_NUMBER() OVER (PARTITION BY s.user_id ORDER BY first_service_timestamp) AS service_number
FROM
  first_services_g s
LEFT JOIN
  flows f
ON
  s.first_service_flow = f.first_service_flow
