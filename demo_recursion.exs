defmodule DemoRecursion do
  @moduledoc """
  Demostración de las funciones recursivas de la Persona A.

  Se ejecuta con: elixir demo_recursion.exs

  No usa procesos ni archivos: llama directamente a la lógica pura de
  `Inventario`, `Solicitudes`, `Cupos` y `Almacen`. La recursión de
  `Despacho` (lanzar y recoger) se ve en demo_conflicto.exs.
  """

  def main do
    Util2.mostrar("=== FUNCIONES RECURSIVAS DE LA PERSONA A ===\n", :mensaje)

    demo_disponible()
    demo_repartir()
    demo_planificar()
    demo_asignado()
    demo_donde_esta()
    demo_almacen()
  end

  # -----------------------------------
  # Datos de prueba
  # -----------------------------------

  # Dos centros con agua: R001 tiene 50 L y R002 tiene 30 L
  defp inventario_de_prueba do
    {:ok, _r1, mapa, _m1} =
      Inventario.registrar(%{}, "R001", "agua", "bebida", 50, "litros", "centro_1")

    {:ok, _r2, mapa, _m2} =
      Inventario.registrar(mapa, "R002", "agua", "bebida", 30, "litros", "centro_2")

    mapa
  end

  # Tres necesidades de agua, ya ordenadas por prioridad (crítica, alta, media)
  defp necesidades_de_prueba do
    {:ok, _n1, mapa} = Solicitudes.registrar(%{}, "agua", 30, "critica", "centro", "Sector 3", "laura")
    {:ok, _n2, mapa} = Solicitudes.registrar(mapa, "agua", 25, "alta", "centro", "Sector 5", "andres")
    {:ok, _n3, mapa} = Solicitudes.registrar(mapa, "agua", 10, "media", "centro", "Sector 7", "ana")

    mapa
    |> Map.values()
    |> Solicitudes.ordenar_por_prioridad()
  end

  # -----------------------------------
  # Inventario.disponible -> sumar_cantidad
  # -----------------------------------

  defp demo_disponible do
    Util2.mostrar("--- 1. Inventario.disponible (usa sumar_cantidad, recursiva) ---", :mensaje)

    total = Inventario.disponible(inventario_de_prueba(), "agua")
    Util2.mostrar("R001 tiene 50 L y R002 tiene 30 L -> agua disponible: #{total} L\n", :mensaje)
  end

  # -----------------------------------
  # Inventario.tomar -> repartir
  # -----------------------------------

  defp demo_repartir do
    Util2.mostrar("--- 2. Inventario.tomar (usa repartir, recursiva) ---", :mensaje)

    mapa = inventario_de_prueba()

    Util2.mostrar("Se piden 70 L:", :mensaje)
    mostrar_toma(Inventario.tomar(mapa, "agua", 70, "demo"))

    Util2.mostrar("Se piden 100 L:", :mensaje)
    mostrar_toma(Inventario.tomar(mapa, "agua", 100, "demo"))

    Util2.mostrar("", :mensaje)
  end

  defp mostrar_toma({:ok, partes, _nuevo_mapa, _movimientos}) do
    Util2.mostrar("  CONFIRMADO, partes tomadas (codigo, litros): #{inspect(partes)}", :mensaje)
  end

  defp mostrar_toma({:error, razon}) do
    Util2.mostrar("  RECHAZADO -> #{razon} (no se descontó nada)", :mensaje)
  end

  # -----------------------------------
  # Solicitudes.planificar
  # -----------------------------------

  defp demo_planificar do
    Util2.mostrar("--- 3. Solicitudes.planificar (recursiva) ---", :mensaje)

    necesidades = necesidades_de_prueba()

    Util2.mostrar("Necesidades en orden de prioridad:", :mensaje)

    necesidades
    |> Util2.convertir_coleccion_mensaje(fn necesidad -> " - #{necesidad}\n" end)
    |> Util2.mostrar(:mensaje)

    plan = Solicitudes.planificar(necesidades, %{"agua" => 50})

    Util2.mostrar("Con 50 L disponibles, el plan de atención (id, recurso, litros) es:", :mensaje)
    Util2.mostrar("  #{inspect(plan)}", :mensaje)
    Util2.mostrar("La alta (25 L) se salta porque después de la crítica solo quedan 20 L.\n", :mensaje)
  end

  # -----------------------------------
  # Solicitudes.asignado -> sumar
  # -----------------------------------

  defp demo_asignado do
    Util2.mostrar("--- 4. Solicitudes.asignado (usa sumar, recursiva) ---", :mensaje)

    [critica | _resto] = necesidades_de_prueba()
    con_partes = %{critica | asignaciones: [{"R001", 20}, {"R002", 5}]}

    Util2.mostrar("Necesidad de #{critica.cantidad} L con asignaciones R001=20 y R002=5:", :mensaje)
    Util2.mostrar("  asignado: #{Solicitudes.asignado(con_partes)} L", :mensaje)
    Util2.mostrar("  restante: #{Solicitudes.restante(con_partes)} L\n", :mensaje)
  end

  # -----------------------------------
  # Cupos.donde_esta -> buscar
  # -----------------------------------

  defp demo_donde_esta do
    Util2.mostrar("--- 5. Cupos.donde_esta (usa buscar, recursiva) ---", :mensaje)

    {:ok, _a1, albergues} = Cupos.registrar(%{}, "A01", "Albergue Norte", "zona_norte", 3)
    {:ok, _a2, albergues} = Cupos.registrar(albergues, "A02", "Albergue Sur", "zona_sur", 5)
    {:ok, _a2, albergues} = Cupos.ingresar(albergues, "A02", "1001")

    Util2.mostrar("Persona 1001 -> #{inspect(Cupos.donde_esta(albergues, "1001"))}", :mensaje)
    Util2.mostrar("Persona 9999 -> #{inspect(Cupos.donde_esta(albergues, "9999"))}\n", :mensaje)
  end

  # -----------------------------------
  # Almacen.decodificar_linea -> decodificar
  # -----------------------------------

  defp demo_almacen do
    Util2.mostrar("--- 6. Almacen.decodificar_linea (usa decodificar, recursiva) ---", :mensaje)

    campos = ["R001", "agua", "centro|norte"]
    linea = Almacen.codificar_linea(campos)
    recuperados = Almacen.decodificar_linea(linea)

    Util2.mostrar("Campos originales : #{inspect(campos)}", :mensaje)
    Util2.mostrar("Línea en el archivo: #{linea}", :mensaje)
    Util2.mostrar("Campos recuperados : #{inspect(recuperados)}", :mensaje)
    Util2.mostrar("¿Iguales? #{campos == recuperados}", :mensaje)
  end
end

DemoRecursion.main()

