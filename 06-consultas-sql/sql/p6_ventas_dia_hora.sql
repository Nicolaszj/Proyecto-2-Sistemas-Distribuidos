-- P6. ¿Qué días de la semana y a qué horas se concentran las compras?
-- Fuente: ventas (EC2). dia_semana: 1 = lunes ... 7 = domingo (se calculó en trusted).
SELECT v.dia_semana,
       v.hora,
       COUNT(DISTINCT v.factura)    AS facturas,
       ROUND(SUM(v.importe_gbp), 2) AS ingreso_bruto_gbp
FROM ${db}.ventas v
WHERE NOT v.es_devolucion
GROUP BY v.dia_semana, v.hora
ORDER BY v.dia_semana, v.hora;
