-- P4. ¿En qué países se gasta más en la tienda por cada 1.000 habitantes?
-- Fuentes: ventas (EC2) + clientes y países (RDS) + población, PIB y tasas (URL Banco Mundial y Frankfurter).
SELECT pa.pais,
       pa.poblacion,
       pa.pib_per_capita_usd,
       ROUND(SUM(v.importe_gbp * t.gbp_usd), 2)                         AS ingreso_neto_usd,
       ROUND(SUM(v.importe_gbp * t.gbp_usd) / pa.poblacion * 1000, 4)   AS usd_por_mil_habitantes
FROM ${db}.ventas v
JOIN ${db}.clientes c     ON v.id_cliente = c.id_cliente
JOIN ${db}.paises pa      ON c.pais = pa.pais
JOIN ${db}.tasas_cambio t ON v.fecha = t.fecha
WHERE pa.poblacion IS NOT NULL
GROUP BY pa.pais, pa.poblacion, pa.pib_per_capita_usd
ORDER BY usd_por_mil_habitantes DESC
LIMIT 10;
