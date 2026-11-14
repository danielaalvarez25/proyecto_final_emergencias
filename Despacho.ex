defmodule Despacho do
  @moduledoc """
  Despacho concurrente de asignaciones: un proceso supervisado por solicitud.

  Este módulo ES el DynamicSupervisor (se usa como hijo del supervisor
  raíz con Despacho). Cada solicitud de asignación se ejecuta
  en su propio proceso Task creado con DynamicSupervisor.start_child/2:


  El resultado vuelve al llamador por paso de mensajes. Los procesos son
  :temporary: si uno falla no se reinicia (repetir una asignación podría
  descontar inventario dos veces) y el fallo no afecta a los demás ni al
  supervisor; el llamador recibe {:error, {:proceso_caido, razon}}.

  Aunque las solicitudes corran en paralelo, la consistencia la garantizan
  los GenServer: Necesidades valida cada necesidad y Recursos descuenta
  el inventario de una en una, por eso la cantidad asignada nunca supera
  la disponible.
  """

  @supervisor __MODULE__
  @timeout 10_000

  @doc "Especificación como supervisor: se agrega como hijo con Despacho."
  def child_spec(opts) do
    %{
      id: __MODULE__,
      start: {DynamicSupervisor, :start_link, [[name: Keyword.get(opts, :name, @supervisor), strategy: :one_for_one]]},
      type: :supervisor
    }
  end

  @doc "Lanza la asignación en un proceso supervisado y devuelve un manejador para esperar el resultado."
  def asignar_async(id, recurso, cantidad) do
    llamador = self()
    ref = make_ref()

    tarea = fn -> send(llamador, {:despacho, ref, Necesidades.asignar(id, recurso, cantidad)}) end

    case DynamicSupervisor.start_child(@supervisor, {Task, tarea}) do
      {:ok, pid} -> {:ok, %{ref: ref, monitor: Process.monitor(pid), pid: pid}}
      {:error, razon} -> {:error, razon}
    end
  end

  @doc "Espera el resultado de una asignación lanzada con asignar_async/3."
  def esperar(%{ref: ref, monitor: monitor}, timeout \\ @timeout) do
    receive do
      {:despacho, ref_recibida, resultado} when ref_recibida == ref ->
        Process.demonitor(monitor, [:flush])
        resultado

      {:DOWN, monitor_recibido, :process, _pid, razon} when monitor_recibido == monitor ->
        {:error, {:proceso_caido, razon}}
    after
      timeout ->
        Process.demonitor(monitor, [:flush])
        {:error, :timeout}
    end
  end

  @doc "Asigna y espera el resultado (un proceso supervisado por solicitud)."
  def asignar(id, recurso, cantidad, timeout \\ @timeout) do
    case asignar_async(id, recurso, cantidad) do
      {:ok, manejador} -> esperar(manejador, timeout)
      error -> error
    end
  end

  @doc """
  Lanza TODAS las asignaciones a la vez, cada una en su proceso, y devuelve
  [{id, resultado}]` en el mismo orden de los pedidos. Es la demo del
  conflicto concurrente: con 50 L y pedidos de 30 y 25, solo uno se confirma.
  """
  def asignar_varias(pedidos), do: pedidos |> lanzar([]) |> recoger([])

  # Recursivas sobre la lista de pedidos: primero se lanzan todos y solo
  # después se recogen los resultados, así corren en paralelo.
  # Caso base: no quedan pedidos por lanzar
  defp lanzar([], acumulado), do: Enum.reverse(acumulado)

  # Caso recursivo: se lanza el primer pedido en su propio proceso y se sigue con el resto
  defp lanzar([{id, recurso, cantidad} | resto], acumulado) do
    lanzado =
      case asignar_async(id, recurso, cantidad) do
        {:ok, manejador} -> {id, {:ok, manejador}}
        {:error, razon} -> {id, {:error, razon}}
      end

    lanzar(resto, [lanzado | acumulado])
  end

  # Caso base: no quedan resultados por recoger, se devuelven en el orden de los pedidos
  defp recoger([], acumulado), do: Enum.reverse(acumulado)

  # Caso recursivo: se espera el resultado del primer pedido y se sigue con el resto
  defp recoger([{id, {:ok, manejador}} | resto], acumulado) do
    recoger(resto, [{id, esperar(manejador)} | acumulado])
  end

  defp recoger([{id, {:error, razon}} | resto], acumulado) do
    recoger(resto, [{id, {:error, razon}} | acumulado])
  end

  @doc "Cantidad de procesos de asignación activos en este momento."
  def activos, do: DynamicSupervisor.count_children(@supervisor).active
end
