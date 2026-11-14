defmodule DemoAlbergues do
  @moduledoc """
  Demostración de la capacidad de un albergue con ingresos simultáneos.

  Se ejecuta con: elixir demo_albergues.exs

  El albergue A01 tiene capacidad para 3 personas y llegan 5 al mismo
  tiempo, cada una en su propio proceso (Task). Solo ingresan 3: la
  ocupación nunca supera la capacidad máxima, porque el GenServer
  Albergues atiende los ingresos de uno en uno.
  """

  @carpeta_datos "data_demo"
  @capacidad 3
  @personas 5

  def main do
    preparar_datos()
    {:ok, _supervisor} = Sistema.iniciar()

    {:ok, albergue} = Albergues.registrar("A01", "Albergue Norte", "zona_norte", @capacidad)
    Util2.mostrar("=== DEMOSTRACIÓN DE ALBERGUES ===\n", :mensaje)
    Util2.mostrar("Albergue registrado -> #{albergue}\n", :mensaje)

    Util2.mostrar("Llegan #{@personas} personas al mismo tiempo...\n", :mensaje)

    resultados = ingresar_simultaneamente()
    Enum.each(resultados, &mostrar_ingreso/1)

    mostrar_estado()
    liberar_un_cupo(resultados)
    mostrar_estado()
    mostrar_reporte()
  end

  defp preparar_datos do
    File.rm_rf(@carpeta_datos)
    Application.put_env(:emergencias, :data_dir, @carpeta_datos)
  end

  # Cada persona ingresa desde su propio proceso
  defp ingresar_simultaneamente do
    1..@personas
    |> Enum.map(fn numero ->
      documento = "100#{numero}"
      Task.async(fn -> {documento, Albergues.ingresar("A01", documento)} end)
    end)
    |> Enum.map(&Task.await/1)
  end

  defp mostrar_ingreso({documento, {:ok, albergue}}) do
    Util2.mostrar(
      "Documento #{documento}: INGRESÓ    -> ocupación #{albergue.ocupacion}/#{albergue.capacidad}",
      :mensaje
    )
  end

  defp mostrar_ingreso({documento, {:error, razon}}) do
    Util2.mostrar("Documento #{documento}: RECHAZADO -> #{razon}", :mensaje)
  end

  # Sale la primera persona que ingresó y entra la primera que había sido rechazada
  defp liberar_un_cupo(resultados) do
    {admitido, _} = Enum.find(resultados, fn {_doc, resultado} -> match?({:ok, _}, resultado) end)
    {rechazado, _} = Enum.find(resultados, fn {_doc, resultado} -> match?({:error, _}, resultado) end)

    Util2.mostrar("\nSale el documento #{admitido} (register_exit)...", :mensaje)
    {:ok, _albergue} = Albergues.salir("A01", admitido)

    Util2.mostrar("Ahora ingresa el documento #{rechazado} (register_entry)...", :mensaje)
    {:ok, _albergue} = Albergues.ingresar("A01", rechazado)
  end

  defp mostrar_estado do
    {:ok, albergue} = Albergues.consultar("A01")
    resumen = Cupos.resumen(albergue)

    Util2.mostrar(
      "\nEstado de A01 -> ocupación #{resumen.ocupacion}/#{resumen.capacidad}, " <>
        "cupos libres #{resumen.cupos}, #{resumen.porcentaje}% de ocupación",
      :mensaje
    )
  end

  defp mostrar_reporte do
    {:ok, albergues} = Albergues.reporte_ocupacion(3)

    Util2.mostrar("\nAlbergues con mayor ocupación:", :mensaje)

    albergues
    |> Util2.convertir_coleccion_mensaje(fn albergue -> " - #{albergue}\n" end)
    |> Util2.mostrar(:mensaje)
  end
end

DemoAlbergues.main()
