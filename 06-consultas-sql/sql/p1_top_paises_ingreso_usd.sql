-- P1. ¿Cuáles son los 10 países con mayor ingreso neto en dólares?
-- Fuentes: ventas (EC2) + clientes (RDS) + tasas de cambio (URL Frankfurter).
-- ${db} se reemplaza por la base de cada motor: retail_trusted (Athena/SparkSQL) o retail_hive (Hive).
SELECT c.pais,
       ROUND(SUM(v.importe_gbp * t.gbp_usd), 2) AS ingreso_neto_usd,
       ROUND(SUM(v.importe_gbp), 2)             AS ingreso_neto_gbp,
       COUNT(DISTINCT v.id_cliente)             AS clientes
FROM ${db}.ventas v
JOIN ${db}.clientes c     ON v.id_cliente = c.id_cliente
JOIN ${db}.tasas_cambio t ON v.fecha = t.fecha
GROUP BY c.pais
ORDER BY ingreso_neto_usd DESC
LIMIT 10;
