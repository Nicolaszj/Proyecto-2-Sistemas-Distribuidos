-- PUNTO 2 - Esquema de la base de datos fuente (RDS MariaDB).
-- Simula el ERP de la empresa: los "datos maestros" de clientes, productos y
-- países. preparar_fuentes.py pega debajo de este esquema los INSERT y la EC2
-- lo ejecuta contra el RDS al arrancar. Es idempotente: se puede correr 2 veces.
-- Los nombres están en inglés a propósito (así vienen del sistema origen);
-- en la zona trusted se estandarizan al español (punto 4).

SET NAMES utf8mb4;  -- el archivo está en UTF-8 (tildes de las regiones)
CREATE DATABASE IF NOT EXISTS retaildb;
ALTER DATABASE retaildb CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
USE retaildb;

DROP TABLE IF EXISTS customers;
DROP TABLE IF EXISTS products;
DROP TABLE IF EXISTS countries;

-- Países donde vende la empresa + región comercial asignada por el negocio.
CREATE TABLE countries (
    country      VARCHAR(60)  NOT NULL PRIMARY KEY,  -- nombre como viene en las ventas
    iso3         CHAR(3)      NULL,                  -- ISO-3166 alfa-3 (cruce con Banco Mundial)
    sales_region VARCHAR(40)  NOT NULL               -- región comercial (dato del negocio)
) DEFAULT CHARSET = utf8mb4;

-- Clientes registrados (solo los que tienen CustomerID en el dataset).
CREATE TABLE customers (
    customer_id  INT          NOT NULL PRIMARY KEY,
    country      VARCHAR(60)  NOT NULL,
    CONSTRAINT fk_customer_country FOREIGN KEY (country) REFERENCES countries(country)
) DEFAULT CHARSET = utf8mb4;

-- Catálogo de productos (código de inventario + descripción).
CREATE TABLE products (
    stock_code   VARCHAR(20)  NOT NULL PRIMARY KEY,
    description  VARCHAR(255) NULL
) DEFAULT CHARSET = utf8mb4;
