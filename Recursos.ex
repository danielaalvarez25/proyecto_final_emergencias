defmodule Recursos do
  @moduledoc """
  GenServer del inventario de recursos.

  Todas las operaciones pasan por el buzón de este único proceso, que las
  atiende de una en una. Por eso, cuando dos solicitudes intentan tomar
  las últimas unidades de un recurso al mismo tiempo, la segunda ve el
  inventario ya descontado y recibe {:error, :stock_insuficiente}:
  la cantidad asignada nunca supera la disponible.

  La lógica vive en Inventario (funciones puras); este
  módulo mantiene el estado y lo persiste con Almacen:

    * recursos.txt: estado actual, una línea por recurso.
    * movimientos_recursos.txt: historial de entradas, salidas y
      transferencias.

  Si falla la escritura en disco se registra un error en el log y el
  proceso sigue atendiendo con el estado en memoria.
  """

  use GenServer
  require Logger

  @archivo "recursos.txt"
  @archivo_movimientos "movimientos_recursos.txt"



  @doc "Inicia el servidor. Opción :name (por defecto el nombre del módulo)."
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, :ok, name: Keyword.get(opts, :name, __MODULE__))
  end


  def registrar(codigo, nombre, categoria, cantidad, unidad, ubicacion, servidor \\ __MODULE__) do
    GenServer.call(servidor, {:registrar, codigo, nombre, categoria, cantidad, unidad, ubicacion})
  end

  @doc """
  Registra una entrada de inventario (suma a la cantidad del recurso).
  """
  def entrada(codigo, cantidad, detalle \\ "", servidor \\ __MODULE__) do
    GenServer.call(servidor, {:entrada, codigo, cantidad, detalle})
  end

  @doc """
  Registra una salida de inventario. Nunca deja la cantidad negativa:
  si no alcanza responde {:error, :stock_insuficiente}.


  """
  def salida(codigo, cantidad, detalle \\ "", servidor \\ __MODULE__) do
    GenServer.call(servidor, {:salida, codigo, cantidad, detalle})
  end

  @doc """
  Toma cantidad` de un recurso por nombre (todo o nada). Devuelve
  {:ok, [{codigo, cantidad_tomada}]} o {:error, :stock_insuficiente}.

  """
  def tomar(nombre, cantidad, motivo \\ "", servidor \\ __MODULE__) do
    GenServer.call(servidor, {:tomar, nombre, cantidad, motivo})
  end

  @doc """
  Transfiere recursos entre centros de apoyo (comando transfer_resource).
  """

  def transferir(codigo, origen, destino, cantidad, servidor \\ __MODULE__) do
    GenServer.call(servidor, {:transferir, codigo, origen, destino, cantidad})
  end

  @doc "Consulta un recurso por su código."
  def consultar(codigo, servidor \\ __MODULE__) do
    GenServer.call(servidor, {:consultar, codigo})
  end

  @doc "Lista recursos (comando list_resources). Filtros: :nombre, :ubicacion, :categoria."
  def listar(filtros \\ [], servidor \\ __MODULE__) do
    GenServer.call(servidor, {:listar, filtros})
  end

  @doc "Cantidad total disponible de un recurso por nombre, sumando todas las ubicaciones."
  def disponible(nombre, servidor \\ __MODULE__) do
    GenServer.call(servidor, {:disponible, nombre})
  end

  @doc "Recursos con cantidad menor o igual al umbral (comando critical_resources)."
  def criticos(umbral \\ 20, servidor \\ __MODULE__) do
    GenServer.call(servidor, {:criticos, umbral})
  end

  @doc "Historial de movimientos de un recurso, del más antiguo al más reciente."
  def historial(codigo, servidor \\ __MODULE__) do
    GenServer.call(servidor, {:historial, codigo})
  end

  # callbacks

  @impl true
  def init(:ok), do: {:ok, cargar()}

  @impl true
  def handle_call({:registrar, codigo, nombre, categoria, cantidad, unidad, ubicacion}, _from, mapa) do
    mapa
    |> Inventario.registrar(codigo, nombre, categoria, cantidad, unidad, ubicacion)
    |> ejecutar(mapa)
  end

  def handle_call({:entrada, codigo, cantidad, detalle}, _from, mapa) do
    mapa |> Inventario.entrada(codigo, cantidad, detalle) |> ejecutar(mapa)
  end

  def handle_call({:salida, codigo, cantidad, detalle}, _from, mapa) do
    mapa |> Inventario.salida(codigo, cantidad, detalle) |> ejecutar(mapa)
  end

  def handle_call({:tomar, nombre, cantidad, motivo}, _from, mapa) do
    mapa |> Inventario.tomar(nombre, cantidad, motivo) |> ejecutar(mapa)
  end

  def handle_call({:transferir, codigo, origen, destino, cantidad}, _from, mapa) do
    mapa |> Inventario.transferir(codigo, origen, destino, cantidad) |> ejecutar(mapa)
  end

  def handle_call({:consultar, codigo}, _from, mapa) do
    {:reply, Inventario.obtener(mapa, codigo), mapa}
  end

  def handle_call({:listar, filtros}, _from, mapa) do
    {:reply, {:ok, Inventario.listar(mapa, filtros)}, mapa}
  end

  def handle_call({:disponible, nombre}, _from, mapa) do
    {:reply, {:ok, Inventario.disponible(mapa, nombre)}, mapa}
  end

  def handle_call({:criticos, umbral}, _from, mapa) do
    {:reply, {:ok, Inventario.criticos(mapa, umbral)}, mapa}
  end

  def handle_call({:historial, codigo}, _from, mapa) do
    respuesta =
      case Inventario.obtener(mapa, codigo) do
        {:ok, recurso} -> {:ok, Enum.reverse(recurso.historial)}
        error -> error
      end

    {:reply, respuesta, mapa}
  end

  #Privadas

  # Aplica el resultado de una operación pura: si salió bien, guarda el
  # nuevo estado y lo persiste, si no, deja el estado intacto.
  defp ejecutar({:ok, valor, nuevo_mapa, movimientos}, _mapa) do
    case persistir(nuevo_mapa, movimientos) do
      :ok -> :ok
      {:error, razon} -> Logger.error("No se pudo guardar el inventario: #{inspect(razon)}")
    end

    {:reply, {:ok, valor}, nuevo_mapa}
  end

  defp ejecutar({:error, razon}, mapa), do: {:reply, {:error, razon}, mapa}

  defp persistir(mapa, movimientos) do
    filas =
      mapa
      |> Map.values()
      |> Enum.sort_by(& &1.codigo)
      |> Enum.map(&Inventario.a_fila/1)

    fecha = DateTime.utc_now() |> DateTime.to_iso8601()

    case Almacen.reescribir(@archivo, filas) do
      :ok ->
        Enum.reduce_while(movimientos, :ok, fn {codigo, tipo, cantidad, detalle}, :ok ->
          case Almacen.agregar(@archivo_movimientos, [codigo, tipo, cantidad, detalle, fecha]) do
            :ok -> {:cont, :ok}
            error -> {:halt, error}
          end
        end)

      error ->
        error
    end
  end

  # Reconstruye el inventario desde los archivos al arrancar.
  defp cargar do
    mapa =
      case Almacen.leer(@archivo) do
        {:ok, filas} ->
          filas
          |> Enum.map(&Inventario.desde_fila/1)
          |> Enum.flat_map(fn
            {:ok, recurso} -> [recurso]
            :error -> []
          end)
          |> Map.new(&{&1.codigo, &1})

        {:error, _razon} ->
          %{}
      end

    case Almacen.leer(@archivo_movimientos) do
      {:ok, filas} -> Enum.reduce(filas, mapa, &agregar_historial/2)
      {:error, _razon} -> mapa
    end
  end

  defp agregar_historial(fila, mapa) do
    case Inventario.desde_fila_movimiento(fila) do
      {:ok, codigo, movimiento} ->
        case Map.fetch(mapa, codigo) do
          {:ok, %Recurso{} = recurso} ->
            Map.put(mapa, codigo, %{recurso | historial: [movimiento | recurso.historial]})

          _ ->
            mapa
        end

      _ ->
        mapa
    end
  end
end
