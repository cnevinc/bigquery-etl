CREATE TEMP FUNCTION udf_static_normalized_os_name() AS (
  ARRAY<STRUCT<os_name STRING, normalized_os_name STRING>>[
    ('Windows_NT', 'Windows'),
    ('Windows_98', 'Windows'),
    ('Windows_95', 'Windows'),
    ('Darwin', 'Mac'),
    ('Android', 'Android'),
    ('iOS', 'iOS'),
    ('iPhoneOS', 'iOS'),
    ('Linux', 'Linux'),
    ('SunOS', 'Linux'),
    ('OpenBSD', 'Linux'),
    ('FreeBSD', 'Linux'),
    ('NetBSD', 'Linux')
  ]
);
