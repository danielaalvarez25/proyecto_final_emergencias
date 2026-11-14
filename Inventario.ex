defmodule Inventario do
  @moduledoc """
  Lógica pura del inventario de recursos (sin procesos ni archivos).

  Trabaja sobre un mapa %{codigo => %Recurso{}} y nunca lo modifica:
  cada operación devuelve un mapa nuevo. Esto permite probarla sin
  GenServer y que el GenServer solo se ocupe de serializar el acceso.

  Retorno de las operaciones que cambian el inventario:

      {:ok, valor, nuevo_mapa, movimientos} | {:error, razon}

  donde movimientos es la lista de {codigo, tipo, cantidad, detalle}
  que el llamador debe persistir.
  """

  #  Registro y consulta

  @doc "Registra un recurso nuevo. La cantidad inicial puede ser 0."
  def registrar(mapa, codigo, nombre, categoria, cantidad, unidad, ubicacion) do
    cond do
      !(Enum.all?([codigo, nombre, unidad, ubicacion], &texto_valido?/1) and
          is_binary(categoria)) ->
        {:error, :datos_invalidos}

      !(is_integer(cantidad) and cantidad >= 0) ->
        {:error, :cantidad_invalida}

      Map.has_key?(mapa, codigo) ->
        {:error, :codigo_duplicado}

      true ->
        historial = if cantidad > 0, do: [{:entrada, cantidad, "registro inicial"}], else: []
        movimientos = if cantidad > 0, do: [{codigo, :entrada, cantidad, "registro inicial"}], else: []

        recurso = %Recurso{
          codigo: codigo,
          nombre: nombre,
          categoria: categoria,
          cantidad: cantidad,
          unidad: unidad,
          ubicacion: ubicacion,
          historial: historial
        }

        {:ok, recurso, Map.put(mapa, codigo, recurso), movimientos}
    end
  end

  @doc "Busca un recurso por código."
  def obtener(mapa, codigo) do
    case Map.fetch(mapa, codigo) do
      {:ok, recurso} -> {:ok, recurso}
      :error -> {:error, :no_existe}
    end
  end

  @doc """
  Lista recursos ordenados por código. Filtros opcionales (keyword):
  :nombre`, :ubicacion, :categoria.
  """
  def listar(mapa, filtros \\ []) do
    mapa
    |> Map.values()
    |> Enum.filter(&cumple_filtros?(&1, filtros))
    |> Enum.sort_by(& &1.codigo)
  end

  @doc "Recursos con cantidad menor o igual al umbral, los más escasos primero."
  def criticos(mapa, umbral) do
    mapa
    |> Map.values()
    |> Enum.filter(&(&1.cantidad <= umbral))
    |> Enum.sort_by(&{&1.cantidad, &1.codigo})
  end

  @doc "Cantidad total disponible de un recurso por nombre, sumando todas las ubicaciones."
  def disponible(mapa, nombre) do
    mapa |> Map.values() |> sumar_cantidad(normalizar(nombre), 0)
  end

  # Recursiva: recorre la lista acumulando la cantidad de los recursos con ese nombre.
  # Caso base: lista vacía, se devuelve lo acumulado
  defp sumar_cantidad([], _nombre, acumulado), do: acumulado

  # Caso recursivo: si el nombre coincide se suma su cantidad, y se sigue con el resto
  defp sumar_cantidad([recurso | resto], nombre, acumulado) do
    if normalizar(recurso.nombre) == nombre do
      sumar_cantidad(resto, nombre, acumulado + recurso.cantidad)
    else
      sumar_cantidad(resto, nombre, acumulado)
    end
  end

  # Entradas y salidas

  @doc "Registra una entrada de inventario."
  def entrada(mapa, codigo, cantidad, detalle \\ "") do
    case validar_cantidad(cantidad) do
      :ok ->
        case obtener(mapa, codigo) do
          {:ok, recurso} ->
            nuevo = aplicar(mapa, recurso, recurso.cantidad + cantidad, :entrada, cantidad, detalle)
            {:ok, Map.fetch!(nuevo, codigo), nuevo, [{codigo, :entrada, cantidad, detalle}]}

          error ->
            error
        end

      error ->
        error
    end
  end

  @doc "Registra una salida de inventario. Nunca deja la cantidad negativa."
  def salida(mapa, codigo, cantidad, detalle \\ "") do
    case validar_cantidad(cantidad) do
      :ok ->
        case obtener(mapa, codigo) do
          {:ok, recurso} ->
            case validar_stock(recurso, cantidad) do
              :ok ->
                nuevo = aplicar(mapa, recurso, recurso.cantidad - cantidad, :salida, cantidad, detalle)
                {:ok, Map.fetch!(nuevo, codigo), nuevo, [{codigo, :salida, cantidad, detalle}]}

              error ->
                error
            end

          error ->
            error
        end

      error ->
        error
    end
  end

  #  Asignación a necesidades
  @doc """
  Toma cantidad de un recurso por nombre, repartiéndola entre los
  centros que lo tengan (en orden de código). Es todo o nada: si el total
  disponible no alcanza, no se descuenta nada.

  El valor devuelto es la lista `[{codigo, cantidad_tomada}]`.
  """
  def tomar(mapa, nombre, cantidad, motivo \\ "") do
    case validar_cantidad(cantidad) do
      :ok ->
        case repartir(candidatos(mapa, nombre), cantidad, []) do
          {:ok, partes} ->
            {nuevo, movimientos} =
              Enum.reduce(partes, {mapa, []}, fn {codigo, tomado}, {actual, acc} ->
                recurso = Map.fetch!(actual, codigo)

                {aplicar(actual, recurso, recurso.cantidad - tomado, :salida, tomado, motivo),
                 [{codigo, :salida, tomado, motivo} | acc]}
              end)

            {:ok, partes, nuevo, Enum.reverse(movimientos)}

          error ->
            error
        end

      error ->
        error
    end
  end

  @doc """
  Reparte restante entre los recursos de la lista, tomando de cada uno
  lo que tenga hasta cubrir la cantidad pedida. Recursiva sobre la lista.
  """
  # Caso base: ya no falta nada por repartir, se devuelven las partes tomadas
  def repartir(_recursos, 0, acumulado), do: {:ok, Enum.reverse(acumulado)}
  # Caso base: se acabaron los recursos y todavía falta, no alcanza el inventario
  def repartir([], _restante, _acumulado), do: {:error, :stock_insuficiente}

  # Caso recursivo: se toma del primer recurso lo que tenga (hasta lo que falta)
  # y se sigue con el resto de la lista
  def repartir([recurso | resto], restante, acumulado) do
    tomado = min(recurso.cantidad, restante)
    repartir(resto, restante - tomado, [{recurso.codigo, tomado} | acumulado])
  end

  #  Transferencias

  @doc """
  Transfiere cantidad del recurso codigo desde su ubicación origen
  hacia destino. Si en el destino ya hay un recurso con el mismo nombre
  y unidad se le suma; si no, se crea uno con código CODIGO@destino.
  """
  def transferir(mapa, codigo, origen, destino, cantidad) do
    case validar_cantidad(cantidad) do
      :ok ->
        case obtener(mapa, codigo) do
          {:ok, fuente} ->
            case validar_transferencia(fuente, origen, destino, cantidad) do
              :ok -> mover(mapa, fuente, origen, destino, cantidad)
              error -> error
            end

          error ->
            error
        end

      error ->
        error
    end
  end

  # Devuelve :ok o el primer error: origen, destino y stock, en ese orden
  defp validar_transferencia(fuente, origen, destino, cantidad) do
    [
      validar_origen(fuente, origen),
      validar_destino(fuente, destino),
      validar_stock(fuente, cantidad)
    ]
    |> Enum.find(:ok, fn resultado -> resultado != :ok end)
  end

  defp mover(mapa, fuente, origen, destino, cantidad) do
    case acreditar_destino(mapa, fuente, destino, cantidad, origen) do
      {:ok, con_destino, codigo_destino} ->
        nuevo =
          aplicar(
            con_destino,
            fuente,
            fuente.cantidad - cantidad,
            :transferencia,
            cantidad,
            "hacia #{destino}"
          )

        valor = %{
          origen: Map.fetch!(nuevo, fuente.codigo),
          destino: Map.fetch!(nuevo, codigo_destino)
        }

        movimientos = [
          {fuente.codigo, :transferencia, cantidad, "hacia #{destino}"},
          {codigo_destino, :transferencia, cantidad, "desde #{origen}"}
        ]

        {:ok, valor, nuevo, movimientos}

      error ->
        error
    end
  end

  defp acreditar_destino(mapa, fuente, destino, cantidad, origen) do
    detalle = "desde #{origen}"

    case buscar_destino(mapa, fuente, destino) do
      %Recurso{} = existente ->
        nuevo =
          aplicar(mapa, existente, existente.cantidad + cantidad, :transferencia, cantidad, detalle)

        {:ok, nuevo, existente.codigo}

      nil ->
        codigo = "#{fuente.codigo}@#{destino}"

        if Map.has_key?(mapa, codigo) do
          {:error, :codigo_duplicado}
        else
          creado = %Recurso{
            codigo: codigo,
            nombre: fuente.nombre,
            categoria: fuente.categoria,
            cantidad: cantidad,
            unidad: fuente.unidad,
            ubicacion: destino,
            historial: [{:transferencia, cantidad, detalle}]
          }

          {:ok, Map.put(mapa, codigo, creado), codigo}
        end
    end
  end

  defp buscar_destino(mapa, fuente, destino) do
    mapa
    |> Map.values()
    |> Enum.find(fn recurso ->
      normalizar(recurso.ubicacion) == normalizar(destino) and
        normalizar(recurso.nombre) == normalizar(fuente.nombre) and
        recurso.unidad == fuente.unidad
    end)
  end

  # Conversión a filas de texto

  @doc "Convierte un recurso en la fila que guarda Almacen."
  def a_fila(%Recurso{} = recurso) do
    [
      recurso.codigo,
      recurso.nombre,
      recurso.categoria,
      recurso.cantidad,
      recurso.unidad,
      recurso.ubicacion
    ]
  end

  @doc "Reconstruye un recurso desde su fila. Una fila dañada devuelve :error."
  def desde_fila([codigo, nombre, categoria, cantidad, unidad, ubicacion]) do
    case Integer.parse(cantidad) do
      {n, ""} when n >= 0 ->
        {:ok,
         %Recurso{
           codigo: codigo,
           nombre: nombre,
           categoria: categoria,
           cantidad: n,
           unidad: unidad,
           ubicacion: ubicacion
         }}

      _ ->
        :error
    end
  end

  def desde_fila(_otra), do: :error

  @doc "Reconstruye {codigo, {tipo, cantidad, detalle}} desde una fila de movimientos."
  def desde_fila_movimiento([codigo, tipo, cantidad, detalle | _fecha]) do
    case parsear_tipo(tipo) do
      {:ok, tipo} ->
        case Integer.parse(cantidad) do
          {n, ""} -> {:ok, codigo, {tipo, n, detalle}}
          _ -> :error
        end

      :error ->
        :error
    end
  end

  def desde_fila_movimiento(_otra), do: :error

  defp parsear_tipo("entrada"), do: {:ok, :entrada}
  defp parsear_tipo("salida"), do: {:ok, :salida}
  defp parsear_tipo("transferencia"), do: {:ok, :transferencia}
  defp parsear_tipo(_otro), do: :error

  # Auxiliares
  defp aplicar(mapa, %Recurso{} = recurso, nuevo_stock, tipo, cantidad, detalle) do
    actualizado = %{
      recurso
      | cantidad: nuevo_stock,
        historial: [{tipo, cantidad, detalle} | recurso.historial]
    }

    Map.put(mapa, recurso.codigo, actualizado)
  end

  defp candidatos(mapa, nombre) do
    objetivo = normalizar(nombre)

    mapa
    |> Map.values()
    |> Enum.filter(&(normalizar(&1.nombre) == objetivo and &1.cantidad > 0))
    |> Enum.sort_by(& &1.codigo)
  end

  defp cumple_filtros?(recurso, filtros) do
    Enum.all?(filtros, fn
      {:nombre, valor} -> normalizar(recurso.nombre) == normalizar(valor)
      {:ubicacion, valor} -> normalizar(recurso.ubicacion) == normalizar(valor)
      {:categoria, valor} -> normalizar(recurso.categoria) == normalizar(valor)
      _otro -> true
    end)
  end

  defp validar_cantidad(cantidad) when is_integer(cantidad) and cantidad > 0, do: :ok
  defp validar_cantidad(_cantidad), do: {:error, :cantidad_invalida}

  defp validar_stock(recurso, cantidad) do
    if cantidad <= recurso.cantidad, do: :ok, else: {:error, :stock_insuficiente}
  end

  defp validar_origen(fuente, origen) do
    if texto_valido?(origen) and normalizar(fuente.ubicacion) == normalizar(origen),
      do: :ok,
      else: {:error, :origen_incorrecto}
  end

  defp validar_destino(fuente, destino) do
    if texto_valido?(destino) and normalizar(destino) != normalizar(fuente.ubicacion),
      do: :ok,
      else: {:error, :destino_invalido}
  end

  defp texto_valido?(texto), do: is_binary(texto) and String.trim(texto) != ""

  defp normalizar(texto), do: texto |> to_string() |> String.trim() |> String.downcase()
end
