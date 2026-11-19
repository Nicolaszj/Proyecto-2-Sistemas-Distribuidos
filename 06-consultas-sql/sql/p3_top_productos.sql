-- P3. ¿Cuáles son los 10 productos que más ingreso neto generan?
-- Fuentes: ventas (EC2) + productos (RDS) + tasas de cambio (URL Frankfurter).
-- "Neto" = ventas menos devoluciones (las devoluciones tienen cantidad negativa).
SELECT p.codigo_producto,
       p.descripcion,
       SUM(v.cantidad)                          AS unidades_netas,
       ROUND(SUM(v.importe_gbp), 2)             AS ingreso_neto_gbp,
       ROUND(SUM(v.importe_gbp * t.gbp_usd), 2) AS ingreso_neto_usd
FROM ${db}.ventas v
JOIN ${db}.productos p    ON v.codigo_producto = p.codigo_producto
JOIN ${db}.tasas_cambio t ON v.fecha = t.fecha
GROUP BY p.codigo_producto, p.descripcion
ORDER BY ingreso_neto_gbp DESC
LIMIT 10;
