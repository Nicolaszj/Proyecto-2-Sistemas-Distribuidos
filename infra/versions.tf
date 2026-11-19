# Versiones de Terraform y de los "providers" (plugins) que usa el proyecto.
#   aws     -> crea todos los recursos en la cuenta de AWS Academy
#   random  -> genera la clave de la base de datos
#   archive -> empaqueta la Lambda de la API en un .zip
terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.80"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.4"
    }
  }
}

# Las credenciales NO van aquí: Terraform usa las de AWS CloudShell (o las de
# "AWS Details" del Learner Lab copiadas en ~/.aws/credentials si se corre en un PC).
provider "aws" {
  region = var.region

  # Todas las cosas que cree Terraform llevan estas etiquetas: así se
  # reconocen en la consola y se sabe qué borrar.
  default_tags {
    tags = {
      Proyecto = "SI3007-Proyecto2-BigData"
      Equipo   = "Nicolas Zapata, Abraham Navarro, Samuel Henao"
      Gestion  = "terraform"
    }
  }
}
