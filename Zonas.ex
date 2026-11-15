defmodule Zonas do
  use GenServer
  require Logger

  @archivo "zonas.txt"
  @niveles %{
    "critico" => :critico,
    "crítico" => :critico,
    "alto" => :alto,
    "medio" => :medio,
    "bajo" => :bajo
  }

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, :ok, name: Keyword.get(opts, :name, __MODULE__))
  end

  def registrar(codigo, nombre, nivel, personas_estimadas \\ 0, servidor \\ __MODULE__) do
    GenServer.call(
      servidor,
      {:registrar, codigo, nombre, nivel, personas_estimadas}
    )
  end

  def agregar_sector(codigo_zona, nombre, personas_estimadas \\ 0, servidor \\ __MODULE__) do
    GenServer.call(
      servidor,
      {:agregar_sector, codigo_zona, nombre, personas_estimadas}
    )
  end

  def agregar_punto(
        codigo_zona,
        nombre_sector,
        nombre_punto,
        personas_estimadas \\ 0,
        servidor \\ __MODULE__
      ) do
    GenServer.call(
      servidor,
      {:agregar_punto, codigo_zona, nombre_sector, nombre_punto, personas_estimadas}
    )
  end

  def consultar(codigo, servidor \\ __MODULE__) do
    GenServer.call(servidor, {:consultar, codigo})
  end

  def listar(servidor \\ __MODULE__) do
    GenServer.call(servidor, :listar)
  end

  def estadisticas(codigo, servidor \\ __MODULE__) do
    GenServer.call(servidor, {:estadisticas, codigo})
  end

  @impl true
  def init(:ok) do
    {:ok, cargar()}
  end

  @impl true
  def handle_call(
        {:registrar, codigo, nombre, nivel, cantidad},
        _from,
        zonas
      ) do
    with true <- texto_valido?(codigo),
         true <- texto_valido?(nombre),
         {:ok, nivel} <- convertir_nivel(nivel),
         :ok <- validar_cantidad(cantidad),
         false <- Map.has_key?(zonas, String.trim(codigo)) do
      zona =
        Zona.crear(
          String.trim(codigo),
          String.trim(nombre),
          nivel,
          cantidad
        )

      nuevas_zonas = Map.put(zonas, zona.codigo, zona)
      guardar(nuevas_zonas)

      {:reply, {:ok, zona}, nuevas_zonas}
    else
      true -> {:reply, {:error, :zona_duplicada}, zonas}
      false -> {:reply, {:error, :datos_invalidos}, zonas}
      {:error, razon} -> {:reply, {:error, razon}, zonas}
    end
  end

  def handle_call(
        {:agregar_sector, codigo_zona, nombre, cantidad},
        _from,
        zonas
      ) do
    with true <- texto_valido?(nombre),
         :ok <- validar_cantidad(cantidad),
         {:ok, zona} <- buscar_zona(zonas, codigo_zona),
         false <-
           Enum.any?(zona.sectores, fn sector ->
             normalizar(sector.nombre) == normalizar(nombre)
           end) do
      sector = Sector.crear(String.trim(nombre), cantidad)
      zona = %{zona | sectores: [sector | zona.sectores]}
      nuevas_zonas = Map.put(zonas, zona.codigo, zona)
      guardar(nuevas_zonas)

      {:reply, {:ok, sector}, nuevas_zonas}
    else
      true -> {:reply, {:error, :sector_duplicado}, zonas}
      false -> {:reply, {:error, :nombre_invalido}, zonas}
      {:error, razon} -> {:reply, {:error, razon}, zonas}
    end
  end

  def handle_call(
        {:agregar_punto, codigo_zona, nombre_sector, nombre_punto, cantidad},
        _from,
        zonas
      ) do
    with true <- texto_valido?(nombre_sector),
         true <- texto_valido?(nombre_punto),
         :ok <- validar_cantidad(cantidad),
         {:ok, zona} <- buscar_zona(zonas, codigo_zona),
         %Sector{} = sector <-
           Enum.find(zona.sectores, fn actual ->
             normalizar(actual.nombre) == normalizar(nombre_sector)
           end),
         false <-
           Enum.any?(sector.puntos, fn punto ->
             normalizar(punto.nombre) == normalizar(nombre_punto)
           end) do
      punto = PuntoAtencion.crear(String.trim(nombre_punto), cantidad)

      sectores =
        Enum.map(zona.sectores, fn actual ->
          if normalizar(actual.nombre) == normalizar(nombre_sector) do
            %{actual | puntos: [punto | actual.puntos]}
          else
            actual
          end
        end)

      zona = %{zona | sectores: sectores}
      nuevas_zonas = Map.put(zonas, zona.codigo, zona)
      guardar(nuevas_zonas)

      {:reply, {:ok, punto}, nuevas_zonas}
    else
      nil -> {:reply, {:error, :sector_no_existe}, zonas}
      true -> {:reply, {:error, :punto_duplicado}, zonas}
      false -> {:reply, {:error, :nombre_invalido}, zonas}
      {:error, razon} -> {:reply, {:error, razon}, zonas}
    end
  end

  def handle_call({:consultar, codigo}, _from, zonas) do
    {:reply, buscar_zona(zonas, codigo), zonas}
  end

  def handle_call(:listar, _from, zonas) do
    lista =
      zonas
      |> Map.values()
      |> Enum.sort_by(& &1.codigo)

    {:reply, {:ok, lista}, zonas}
  end

  def handle_call({:estadisticas, codigo}, _from, zonas) do
    case buscar_zona(zonas, codigo) do
      {:ok, zona} ->
        {personas, sectores, puntos} =
          contar_sectores(zona.sectores, 0, 0, 0)

        resultado = %{
          codigo: zona.codigo,
          personas_estimadas: zona.personas_estimadas + personas,
          sectores: sectores,
          puntos_atencion: puntos,
          nivel: zona.nivel
        }

        {:reply, {:ok, resultado}, zonas}

      error ->
        {:reply, error, zonas}
    end
  end

  # Recorre recursivamente los sectores de la zona.
  defp contar_sectores([], personas, sectores, puntos) do
    {personas, sectores, puntos}
  end

  defp contar_sectores([sector | resto], personas, sectores, puntos) do
    {personas_puntos, cantidad_puntos} =
      contar_puntos(sector.puntos, 0, 0)

    contar_sectores(
      resto,
      personas + sector.personas_estimadas + personas_puntos,
      sectores + 1,
      puntos + cantidad_puntos
    )
  end

  # Recorre recursivamente los puntos de atención de un sector.
  defp contar_puntos([], personas, cantidad) do
    {personas, cantidad}
  end

  defp contar_puntos([punto | resto], personas, cantidad) do
    contar_puntos(
      resto,
      personas + punto.personas_estimadas,
      cantidad + 1
    )
  end

  defp buscar_zona(zonas, codigo) do
    case Map.fetch(zonas, String.trim(to_string(codigo))) do
      {:ok, zona} -> {:ok, zona}
      :error -> {:error, :zona_no_existe}
    end
  end

  defp convertir_nivel(nivel) when is_atom(nivel) do
    convertir_nivel(Atom.to_string(nivel))
  end

  defp convertir_nivel(nivel) when is_binary(nivel) do
    nivel = String.downcase(String.trim(nivel))

    case Map.fetch(@niveles, nivel) do
      {:ok, atom} -> {:ok, atom}
      :error -> {:error, :nivel_invalido}
    end
  end

  defp convertir_nivel(_nivel), do: {:error, :nivel_invalido}

  defp validar_cantidad(cantidad)
       when is_integer(cantidad) and cantidad >= 0 do
    :ok
  end

  defp validar_cantidad(_cantidad), do: {:error, :cantidad_invalida}

  defp texto_valido?(texto) do
    is_binary(texto) and String.trim(texto) != ""
  end

  defp normalizar(texto) do
    texto
    |> to_string()
    |> String.trim()
    |> String.downcase()
  end

  defp guardar(zonas) do
    zonas = zonas |> Map.values() |> Enum.sort_by(& &1.codigo)

    filas_zonas =
      Enum.map(zonas, fn zona ->
        ["zona", zona.codigo, zona.nombre, zona.nivel, zona.personas_estimadas]
      end)

    filas_sectores =
      Enum.flat_map(zonas, fn zona ->
        Enum.map(zona.sectores, fn sector ->
          [
            "sector",
            zona.codigo,
            sector.nombre,
            sector.personas_estimadas
          ]
        end)
      end)

    filas_puntos =
      Enum.flat_map(zonas, fn zona ->
        Enum.flat_map(zona.sectores, fn sector ->
          Enum.map(sector.puntos, fn punto ->
            [
              "punto",
              zona.codigo,
              sector.nombre,
              punto.nombre,
              punto.personas_estimadas
            ]
          end)
        end)
      end)

    case Almacen.reescribir(
           @archivo,
           filas_zonas ++ filas_sectores ++ filas_puntos
         ) do
      :ok -> :ok
      {:error, razon} -> Logger.error("No se guardaron las zonas: #{inspect(razon)}")
    end
  end

  defp cargar do
    case Almacen.leer(@archivo) do
      {:ok, filas} ->
        Enum.reduce(filas, %{}, &cargar_fila/2)

      {:error, razon} ->
        Logger.error("No se pudieron leer las zonas: #{inspect(razon)}")
        %{}
    end
  end

  defp cargar_fila(
         ["zona", codigo, nombre, nivel, personas],
         zonas
       ) do
    with {:ok, nivel} <- convertir_nivel(nivel),
         {cantidad, ""} <- Integer.parse(personas),
         true <- cantidad >= 0 do
      zona = Zona.crear(codigo, nombre, nivel, cantidad)
      Map.put(zonas, codigo, zona)
    else
      _ -> zonas
    end
  end

  defp cargar_fila(
         ["sector", codigo_zona, nombre, personas],
         zonas
       ) do
    with {:ok, zona} <- buscar_zona(zonas, codigo_zona),
         {cantidad, ""} <- Integer.parse(personas),
         true <- cantidad >= 0 do
      sector = Sector.crear(nombre, cantidad)
      Map.put(zonas, codigo_zona, %{zona | sectores: [sector | zona.sectores]})
    else
      _ -> zonas
    end
  end

  defp cargar_fila(
         ["punto", codigo_zona, nombre_sector, nombre_punto, personas],
         zonas
       ) do
    with {:ok, zona} <- buscar_zona(zonas, codigo_zona),
         {cantidad, ""} <- Integer.parse(personas),
         true <- cantidad >= 0 do
      punto = PuntoAtencion.crear(nombre_punto, cantidad)

      sectores =
        Enum.map(zona.sectores, fn sector ->
          if normalizar(sector.nombre) == normalizar(nombre_sector) do
            %{sector | puntos: [punto | sector.puntos]}
          else
            sector
          end
        end)

      Map.put(zonas, codigo_zona, %{zona | sectores: sectores})
    else
      _ -> zonas
    end
  end

  defp cargar_fila(_fila, zonas), do: zonas
end
