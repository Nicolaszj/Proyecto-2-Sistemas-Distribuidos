-- P5. ¿Qué región comercial devuelve más (en % del valor vendido)?
-- Fuentes: ventas (EC2) + clientes y países con su región comercial (RDS).
-- Las devoluciones son las facturas que empiezan por "C" (es_devolucion = true).
SELECT pa.region_comercial,
       ROUND(SUM(CASE WHEN v.es_devolucion THEN 0 ELSE v.importe_gbp END), 2)      AS ventas_brutas_gbp,
       ROUND(-1 * SUM(CASE WHEN v.es_devolucion THEN v.importe_gbp ELSE 0 END), 2) AS devoluciones_gbp,
       ROUND(100 * (-1 * SUM(CASE WHEN v.es_devolucion THEN v.importe_gbp ELSE 0 END))
                 / SUM(CASE WHEN v.es_devolucion THEN 0 ELSE v.importe_gbp END), 2) AS tasa_devolucion_pct,
       COUNT(DISTINCT CASE WHEN v.es_devolucion THEN v.factura END)                 AS facturas_devueltas
FROM ${db}.ventas v
JOIN ${db}.clientes c ON v.id_cliente = c.id_cliente
JOIN ${db}.paises pa  ON c.pais = pa.pais
GROUP BY pa.region_comercial
ORDER BY tasa_devolucion_pct DESC;
