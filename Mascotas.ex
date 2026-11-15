defmodule Mascotas do
  use GenServer
  require Logger

  @archivo "mascotas.txt"
  @umbral 50
  @pesos %{especie: 30, color: 20, tamano: 10, zona: 20, caracteristicas: 20}
  @tipos [:perdida, :encontrada]

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, :ok, name: Keyword.get(opts, :name, __MODULE__))
  end

  def reportar(tipo, especie, nombre, caracteristicas, color, tamano, zona, contacto, servidor \\ __MODULE__) do
    GenServer.call(
      servidor,
      {:reportar, tipo, especie, nombre, caracteristicas, color, tamano, zona, contacto}
    )
  end

  def listar(filtros \\ [], servidor \\ __MODULE__) do
    GenServer.call(servidor, {:listar, filtros})
  end

  def buscar_coincidencias(umbral \\ @umbral, servidor \\ __MODULE__) do
    GenServer.call(servidor, {:buscar_coincidencias, umbral})
  end

  def confirmar(id_perdida, id_encontrada, servidor \\ __MODULE__) do
    GenServer.call(servidor, {:confirmar, to_string(id_perdida), to_string(id_encontrada)})
  end

  def puntaje(%Mascota{} = perdida, %Mascota{} = encontrada) do
    Enum.reduce(@pesos, 0, fn {campo, peso}, total ->
      valor_perdido = normalizar(Map.fetch!(perdida, campo))
      valor_encontrado = normalizar(Map.fetch!(encontrada, campo))

      if comparable?(valor_perdido) and valor_perdido == valor_encontrado do
        total + peso
      else
        total
      end
    end)
  end

  @impl true
  def init(:ok) do
    reportes = cargar()
    {:ok, %{reportes: reportes, siguiente_id: siguiente_id(reportes)}}
  end

  @impl true
  def handle_call(
        {:reportar, tipo, especie, nombre, caracteristicas, color, tamano, zona, contacto},
        _from,
        estado
      ) do
    with {:ok, tipo} <- convertir_tipo(tipo),
         :ok <- validar_reporte(especie, color, tamano, zona, contacto) do
      id = "MP" <> String.pad_leading(Integer.to_string(estado.siguiente_id), 3, "0")
      nombre = if texto_vacio?(nombre), do: "desconocido", else: String.trim(nombre)
      caracteristicas = if is_binary(caracteristicas), do: String.trim(caracteristicas), else: ""

      reporte =
        Mascota.crear(
          id,
          tipo,
          String.trim(especie),
          nombre,
          caracteristicas,
          String.trim(color),
          String.trim(tamano),
          String.trim(zona),
          String.trim(contacto)
        )

      reportes = Map.put(estado.reportes, id, reporte)
      guardar(reportes)

      {:reply, {:ok, reporte},
       %{estado | reportes: reportes, siguiente_id: estado.siguiente_id + 1}}
    else
      {:error, razon} -> {:reply, {:error, razon}, estado}
    end
  end

  def handle_call({:listar, filtros}, _from, estado) do
    reportes =
      estado.reportes
      |> Map.values()
      |> Enum.filter(&coincide_filtros?(&1, filtros))
      |> Enum.sort_by(& &1.id)

    {:reply, {:ok, reportes}, estado}
  end

  def handle_call({:buscar_coincidencias, umbral}, _from, estado)
      when is_integer(umbral) and umbral >= 0 and umbral <= 100 do
    abiertas =
      Enum.filter(
        Map.values(estado.reportes),
        &(&1.estado in [:activa, :posible_coincidencia])
      )

    perdidas = Enum.filter(abiertas, &(&1.tipo == :perdida))
    encontradas = Enum.filter(abiertas, &(&1.tipo == :encontrada))

    coincidencias =
      comparar_listas(perdidas, encontradas, [])
      |> Enum.filter(fn {_perdida, _encontrada, puntos} -> puntos >= umbral end)
      |> Enum.sort_by(fn {_perdida, _encontrada, puntos} -> -puntos end)

    reportes = marcar_posibles(estado.reportes, coincidencias)
    guardar(reportes)

    {:reply, {:ok, coincidencias}, %{estado | reportes: reportes}}
  end

  def handle_call({:buscar_coincidencias, _umbral}, _from, estado) do
    {:reply, {:error, :umbral_invalido}, estado}
  end

  def handle_call({:confirmar, id_perdida, id_encontrada}, _from, estado) do
    with %Mascota{tipo: :perdida, estado: estado_perdida} = perdida <-
           Map.get(estado.reportes, id_perdida),
         %Mascota{tipo: :encontrada, estado: estado_encontrada} = encontrada <-
           Map.get(estado.reportes, id_encontrada),
         true <- estado_perdida in [:activa, :posible_coincidencia],
         true <- estado_encontrada in [:activa, :posible_coincidencia],
         puntos when puntos >= @umbral <- puntaje(perdida, encontrada) do
      perdida = %{perdida | estado: :resuelta, coincidencia: id_encontrada}
      encontrada = %{encontrada | estado: :resuelta, coincidencia: id_perdida}

      reportes =
        estado.reportes
        |> Map.put(id_perdida, perdida)
        |> Map.put(id_encontrada, encontrada)

      guardar(reportes)

      {:reply, {:ok, {perdida, encontrada, puntos}}, %{estado | reportes: reportes}}
    else
      nil -> {:reply, {:error, :reporte_no_existe}, estado}
      false -> {:reply, {:error, :reporte_ya_resuelto}, estado}
      puntos when is_integer(puntos) -> {:reply, {:error, :puntaje_insuficiente}, estado}
      _ -> {:reply, {:error, :tipos_de_reporte_invalidos}, estado}
    end
  end

  # Compara recursivamente cada reporte perdido con la lista de encontrados.
  defp comparar_listas([], _encontradas, acumulado) do
    Enum.reverse(acumulado)
  end

  defp comparar_listas([perdida | resto], encontradas, acumulado) do
    acumulado = comparar_con_encontradas(perdida, encontradas, acumulado)
    comparar_listas(resto, encontradas, acumulado)
  end

  defp comparar_con_encontradas(_perdida, [], acumulado) do
    acumulado
  end

  defp comparar_con_encontradas(perdida, [encontrada | resto], acumulado) do
    coincidencia = {perdida, encontrada, puntaje(perdida, encontrada)}
    comparar_con_encontradas(perdida, resto, [coincidencia | acumulado])
  end

  defp marcar_posibles(reportes, coincidencias) do
    ids =
      Enum.reduce(coincidencias, MapSet.new(), fn {perdida, encontrada, _puntos}, acumulado ->
        acumulado
        |> MapSet.put(perdida.id)
        |> MapSet.put(encontrada.id)
      end)

    Enum.reduce(ids, reportes, fn id, acumulado ->
      Map.update!(acumulado, id, &%{&1 | estado: :posible_coincidencia})
    end)
  end

  defp validar_reporte(especie, color, tamano, zona, contacto) do
    if Enum.all?([especie, color, tamano, zona, contacto], &texto_valido?/1) do
      :ok
    else
      {:error, :datos_invalidos}
    end
  end

  defp convertir_tipo(tipo) when tipo in @tipos, do: {:ok, tipo}

  defp convertir_tipo(tipo) when is_binary(tipo) do
    case String.downcase(String.trim(tipo)) do
      "perdida" -> {:ok, :perdida}
      "perdido" -> {:ok, :perdida}
      "lost" -> {:ok, :perdida}
      "found" -> {:ok, :encontrada}
      "encontrada" -> {:ok, :encontrada}
      "encontrado" -> {:ok, :encontrada}
      _ -> {:error, :tipo_reporte_invalido}
    end
  end

  defp convertir_tipo(_), do: {:error, :tipo_reporte_invalido}

  defp convertir_estado(:activa), do: {:ok, :activa}
  defp convertir_estado(:posible_coincidencia), do: {:ok, :posible_coincidencia}
  defp convertir_estado(:resuelta), do: {:ok, :resuelta}
  defp convertir_estado("activa"), do: {:ok, :activa}
  defp convertir_estado("posible_coincidencia"), do: {:ok, :posible_coincidencia}
  defp convertir_estado("resuelta"), do: {:ok, :resuelta}
  defp convertir_estado(_), do: {:error, :estado_invalido}

  defp coincide_filtros?(reporte, filtros) do
    Enum.all?(filtros, fn
      {:tipo, valor} -> convertir_tipo(valor) == {:ok, reporte.tipo}
      {:especie, valor} -> normalizar(reporte.especie) == normalizar(valor)
      {:zona, valor} -> normalizar(reporte.zona) == normalizar(valor)
      {:estado, valor} -> convertir_estado(valor) == {:ok, reporte.estado}
      _ -> true
    end)
  end

  defp guardar(reportes) do
    filas =
      reportes
      |> Map.values()
      |> Enum.sort_by(& &1.id)
      |> Enum.map(fn reporte ->
        [
          reporte.id,
          reporte.tipo,
          reporte.especie,
          reporte.nombre,
          reporte.caracteristicas,
          reporte.color,
          reporte.tamano,
          reporte.zona,
          reporte.contacto,
          reporte.estado,
          reporte.coincidencia || ""
        ]
      end)

    case Almacen.reescribir(@archivo, filas) do
      :ok -> :ok
      {:error, razon} ->
        Logger.error("No se guardaron los reportes de mascotas: #{inspect(razon)}")
    end
  end

  defp cargar do
    case Almacen.leer(@archivo) do
      {:ok, filas} ->
        filas
        |> Enum.flat_map(&desde_fila/1)
        |> Map.new(fn reporte -> {reporte.id, reporte} end)

      {:error, razon} ->
        Logger.error("No se pudieron leer reportes de mascotas: #{inspect(razon)}")
        %{}
    end
  end

  defp desde_fila([
         id,
         tipo,
         especie,
         nombre,
         caracteristicas,
         color,
         tamano,
         zona,
         contacto,
         estado,
         coincidencia
       ]) do
    with {:ok, tipo} <- convertir_tipo(tipo),
         {:ok, estado} <- convertir_estado(estado) do
      reporte =
        Mascota.crear(
          id,
          tipo,
          especie,
          nombre,
          caracteristicas,
          color,
          tamano,
          zona,
          contacto
        )

      [
        %{
          reporte
          | estado: estado,
            coincidencia: if(coincidencia == "", do: nil, else: coincidencia)
        }
      ]
    else
      _ -> []
    end
  end

  defp desde_fila(_), do: []

  defp siguiente_id(reportes) do
    maximo =
      reportes
      |> Map.keys()
      |> Enum.map(fn
        "MP" <> resto ->
          case Integer.parse(resto) do
            {numero, ""} -> numero
            _ -> 0
          end

        _ ->
          0
      end)
      |> Enum.max(fn -> 0 end)

    maximo + 1
  end

  defp texto_valido?(texto) do
    is_binary(texto) and String.trim(texto) != ""
  end

  defp texto_vacio?(texto), do: not texto_valido?(texto)

  defp comparable?(valor) do
    valor != "" and valor not in ["desconocido", "desconocida", "no_sabe"]
  end

  defp normalizar(nil), do: ""

  defp normalizar(valor) do
    valor
    |> to_string()
    |> String.trim()
    |> String.downcase()
    |> :unicode.characters_to_nfd_binary()
    |> String.replace(~r/\p{Mn}/u, "")
  end
end
