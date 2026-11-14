defmodule DemoConflicto do
  @moduledoc """
  Demostración del conflicto concurrente de recursos.

  Se ejecuta con: elixir demo_conflicto.exs

  ## Primera prueba (flujo del enunciado)

  El centro de acopio tiene 50 litros de agua. Al mismo tiempo llegan dos
  solicitudes: una de 30 litros y otra de 25 litros. Solo una se confirma,
  porque nunca se pueden asignar 55 litros cuando solo existen 50.

  ## Segunda prueba

  El centro tiene 50 kg de arroz y llegan 20 solicitudes simultáneas de
  10 kg. Se confirman exactamente 5.

  Cada solicitud se ejecuta en su propio proceso, creado por el
  DynamicSupervisor Despacho. La consistencia la garantizan los GenServer
  Necesidades y Recursos, que atienden los mensajes de uno en uno.
  """

  @carpeta_datos "data_demo"
  @solicitudes_estres 20

  def main do
    preparar_datos()
    {:ok, _supervisor} = Sistema.iniciar()

    primera_prueba()
    segunda_prueba()

    mostrar_archivo("recursos.txt")
    mostrar_archivo("movimientos_recursos.txt")
  end

  # Cada ejecución empieza con los archivos de la demostración vacíos
  defp preparar_datos do
    File.rm_rf(@carpeta_datos)
    Application.put_env(:emergencias, :data_dir, @carpeta_datos)
  end


  # Primera prueba: 30 L y 25 L sobre 50 L

  defp primera_prueba do
    Util2.mostrar("=== PRIMERA PRUEBA: 30 L y 25 L sobre 50 L de agua ===\n", :mensaje)

    {:ok, agua} = Recursos.registrar("R001", "agua", "bebida", 50, "litros", "centro_acopio_1")
    Util2.mostrar("Recurso registrado -> #{agua}", :mensaje)

    [
      {"agua", 30, "critica", "centro", "Punto de atención sector 3", "laura"},
      {"agua", 25, "alta", "centro", "Punto de atención sector 5", "andres"}
    ]
    |> Enum.each(&registrar_necesidad/1)

    Util2.mostrar("\nSe lanzan las dos asignaciones al mismo tiempo...\n", :mensaje)

    [{"N001", "agua", 30}, {"N002", "agua", 25}]
    |> Despacho.asignar_varias()
    |> Enum.each(&mostrar_resultado/1)

    mostrar_resumen_agua()
  end

  defp registrar_necesidad({tipo, cantidad, prioridad, zona, descripcion, responsable}) do
    {:ok, necesidad} =
      Necesidades.registrar(tipo, cantidad, prioridad, zona, descripcion, responsable)

    Util2.mostrar("Necesidad registrada -> #{necesidad}", :mensaje)
  end

  defp mostrar_resultado({id, {:ok, necesidad}}) do
    Util2.mostrar("#{id}: CONFIRMADA -> #{necesidad}", :mensaje)
  end

  defp mostrar_resultado({id, {:error, razon}}) do
    Util2.mostrar("#{id}: RECHAZADA  -> #{razon}", :mensaje)
  end

  defp mostrar_resumen_agua do
    {:ok, agua} = Recursos.consultar("R001")
    {:ok, asignadas} = Necesidades.listar(estado: :asignada)
    {:ok, historial} = Recursos.historial("R001")

    Util2.mostrar("\nInventario final -> #{agua}", :mensaje)
    Util2.mostrar("Necesidades asignadas: #{length(asignadas)} de 2", :mensaje)
    Util2.mostrar("Nunca se asignaron 55 L con solo 50 L disponibles.\n", :mensaje)

    Util2.mostrar("Historial de movimientos de R001:", :mensaje)

    historial
    |> Util2.convertir_coleccion_mensaje(fn {tipo, cantidad, detalle} ->
      " - #{tipo} #{cantidad} (#{detalle})\n"
    end)
    |> Util2.mostrar(:mensaje)
  end


  # Segunda prueba: 20 solicitudes de 10 kg sobre 50 kg

  defp segunda_prueba do
    Util2.mostrar(
      "=== SEGUNDA PRUEBA: #{@solicitudes_estres} solicitudes de 10 kg sobre 50 kg de arroz ===\n",
      :mensaje
    )

    {:ok, arroz} = Recursos.registrar("R002", "arroz", "alimento", 50, "kg", "centro_acopio_1")
    Util2.mostrar("Recurso registrado -> #{arroz}", :mensaje)

    resultados =
      1..@solicitudes_estres
      |> Enum.map(&crear_pedido_arroz/1)
      |> Despacho.asignar_varias()

    confirmadas = Enum.count(resultados, fn {_id, resultado} -> match?({:ok, _}, resultado) end)
    {:ok, arroz} = Recursos.consultar("R002")

    Util2.mostrar("\nSolicitudes confirmadas: #{confirmadas} de #{@solicitudes_estres}", :mensaje)
    Util2.mostrar("Solicitudes rechazadas: #{@solicitudes_estres - confirmadas}", :mensaje)
    Util2.mostrar("Inventario final -> #{arroz}\n", :mensaje)
  end

  defp crear_pedido_arroz(_numero) do
    {:ok, necesidad} =
      Necesidades.registrar("alimentos", 10, "media", "centro", "Reparto de arroz", "voluntario")

    {necesidad.id, "arroz", 10}
  end


  # Persistencia
  
  defp mostrar_archivo(nombre) do
    ruta = Almacen.ruta(nombre)

    case File.read(ruta) do
      {:ok, contenido} ->
        Util2.mostrar("=== Archivo #{ruta} ===\n#{contenido}", :mensaje)

      {:error, razon} ->
        Util2.mostrar("No se pudo leer #{ruta}: #{razon}", :error)
    end
  end
end

DemoConflicto.main()
