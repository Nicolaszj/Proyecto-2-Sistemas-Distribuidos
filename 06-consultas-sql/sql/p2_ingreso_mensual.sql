-- P2. ¿Cómo evolucionó el ingreso mes a mes y cuál fue el mes pico?
-- Fuentes: ventas (EC2) + tasas de cambio (URL Frankfurter).
-- Ticket promedio = ventas (sin devoluciones) / número de facturas de venta.
SELECT YEAR(v.fecha)  AS anio,
       MONTH(v.fecha) AS mes,
       ROUND(SUM(v.importe_gbp), 2)             AS ingreso_neto_gbp,
       ROUND(SUM(v.importe_gbp * t.gbp_usd), 2) AS ingreso_neto_usd,
       COUNT(DISTINCT CASE WHEN NOT v.es_devolucion THEN v.factura END) AS facturas,
       ROUND(SUM(CASE WHEN NOT v.es_devolucion THEN v.importe_gbp END)
             / COUNT(DISTINCT CASE WHEN NOT v.es_devolucion THEN v.factura END), 2) AS ticket_promedio_gbp
FROM ${db}.ventas v
JOIN ${db}.tasas_cambio t ON v.fecha = t.fecha
GROUP BY YEAR(v.fecha), MONTH(v.fecha)
ORDER BY anio, mes;
