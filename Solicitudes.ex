defmodule Solicitudes do
  @moduledoc """
  Lógica pura de las necesidades puntuales (sin procesos ni archivos).

  Trabaja sobre un mapa %{id => %Necesidad{}} y nunca lo modifica: cada
  operación devuelve un mapa nuevo. El GenServer Necesidades
  se ocupa de serializar el acceso y de persistir.

  """

  @tipos [
    :agua,
    :alimentos,
    :medicamentos,
    :primeros_auxilios,
    :refugio,
    :transporte,
    :rescate,
    :otra
  ]

  # De mayor a menor urgencia: el orden de la lista ES el orden de atención.
  @prioridades [:critica, :alta, :media, :baja]

  @estados [:pendiente, :asignada, :en_atencion, :atendida, :cancelada]

  @transiciones %{
    pendiente: [:asignada, :cancelada],
    asignada: [:en_atencion, :atendida, :cancelada],
    en_atencion: [:atendida, :cancelada],
    atendida: [],
    cancelada: []
  }

  def tipos, do: @tipos
  def prioridades, do: @prioridades
  def estados, do: @estados

  # Registro
  @doc """
  Registra una necesidad con identificador único generado (N001, N002).
  tipo, prioridad y estado aceptan átomos o texto ("Crítica", "en atención").
  """
  def registrar(mapa, tipo, cantidad, prioridad, zona, descripcion \\ "", responsable \\ "") do
    case convertir(tipo, @tipos, :tipo_invalido) do
      {:error, razon} ->
        {:error, razon}

      {:ok, tipo} ->
        case convertir(prioridad, @prioridades, :prioridad_invalida) do
          {:error, razon} ->
            {:error, razon}

          {:ok, prioridad} ->
            campos = [
              validar_cantidad(cantidad),
              validar_texto(zona, :zona_invalida),
              validar_opcional(descripcion),
              validar_opcional(responsable)
            ]

            case primer_error(campos) do
              :ok ->
                id = siguiente_id(mapa)

                necesidad = %Necesidad{
                  id: id,
                  tipo: tipo,
                  descripcion: String.trim(descripcion),
                  cantidad: cantidad,
                  zona: String.trim(zona),
                  prioridad: prioridad,
                  responsable: String.trim(responsable),
                  estado: :pendiente,
                  asignaciones: []
                }

                {:ok, necesidad, Map.put(mapa, id, necesidad)}

              error ->
                error
            end
        end
    end
  end

  # Devuelve :ok si todas las validaciones pasaron, o el primer error
  defp primer_error(resultados) do
    Enum.find(resultados, :ok, fn resultado -> resultado != :ok end)
  end

  @doc "Siguiente identificador libre: el mayor número usado más uno."
  def siguiente_id(mapa) do
    numeros = mapa |> Map.keys() |> Enum.map(&numero_id/1)
    maximo = Enum.max([0 | numeros])
    "N" <> String.pad_leading(Integer.to_string(maximo + 1), 3, "0")
  end

  defp numero_id("N" <> resto) do
    case Integer.parse(resto) do
      {n, ""} -> n
      _ -> 0
    end
  end

  defp numero_id(_otro), do: 0

  @doc "Busca una necesidad por id (sin distinguir mayúsculas)."
  def obtener(mapa, id) do
    clave = id |> to_string() |> String.trim() |> String.upcase()

    case Map.fetch(mapa, clave) do
      {:ok, necesidad} -> {:ok, necesidad}
      :error -> {:error, :no_existe}
    end
  end

  # Estados

  @doc "Cambia el estado respetando las transiciones válidas."
  def cambiar_estado(mapa, id, nuevo) do
    case obtener(mapa, id) do
      {:error, razon} ->
        {:error, razon}

      {:ok, necesidad} ->
        case convertir(nuevo, @estados, :estado_invalido) do
          {:error, razon} ->
            {:error, razon}

          {:ok, nuevo} ->
            case validar_transicion(necesidad.estado, nuevo) do
              :ok ->
                actualizada = %{necesidad | estado: nuevo}
                {:ok, actualizada, Map.put(mapa, actualizada.id, actualizada)}

              error ->
                error
            end
        end
    end
  end

  defp validar_transicion(actual, nuevo) do
    cond do
      actual in [:atendida, :cancelada] -> {:error, :necesidad_cerrada}
      nuevo in Map.fetch!(@transiciones, actual) -> :ok
      true -> {:error, :transicion_invalida}
    end
  end

  # Asignación de recursos

  @doc """
  Verifica que se pueda asignar cantidad a la necesidad: debe estar
  pendiente y la cantidad no puede exceder lo que aún le falta.
  Se llama ANTES de descontar inventario.
  """
  def puede_asignar(mapa, id, cantidad) do
    case obtener(mapa, id) do
      {:error, razon} ->
        {:error, razon}

      {:ok, necesidad} ->
        validaciones = [
          validar_abierta(necesidad),
          validar_cantidad(cantidad),
          validar_restante(necesidad, cantidad)
        ]

        case primer_error(validaciones) do
          :ok -> {:ok, necesidad}
          error -> error
        end
    end
  end

  @doc """
  Anota las partes [{codigo_recurso, cantidad}] ya tomadas del inventario.
  Si la necesidad queda cubierta pasa a :asignada; si no, sigue :pendiente.
  """
  def aplicar_asignacion(mapa, id, partes) do
    case obtener(mapa, id) do
      {:ok, necesidad} ->
        cubierta = %{necesidad | asignaciones: necesidad.asignaciones ++ partes}
        estado = if restante(cubierta) <= 0, do: :asignada, else: necesidad.estado
        actualizada = %{cubierta | estado: estado}
        {:ok, actualizada, Map.put(mapa, actualizada.id, actualizada)}

      error ->
        error
    end
  end

  @doc "Cantidad ya asignada a la necesidad (suma recursiva de sus asignaciones)."
  def asignado(necesidad), do: sumar(necesidad.asignaciones, 0)

  # Caso base: lista vacía, se devuelve lo acumulado
  defp sumar([], acumulado), do: acumulado

  # Caso recursivo: se suma la cantidad del primero y se sigue con el resto
  defp sumar([{_codigo, cantidad} | resto], acumulado), do: sumar(resto, acumulado + cantidad)

  @doc "Cantidad que aún le falta a la necesidad."
  def restante(necesidad), do: necesidad.cantidad - asignado(necesidad)

  defp validar_abierta(%{estado: estado}) when estado in [:atendida, :cancelada],
    do: {:error, :necesidad_cerrada}

  defp validar_abierta(%{estado: :pendiente}), do: :ok
  defp validar_abierta(_otra), do: {:error, :ya_asignada}

  defp validar_restante(necesidad, cantidad) do
    if cantidad <= restante(necesidad), do: :ok, else: {:error, :excede_necesidad}
  end

  #Consultas y prioridad

  @doc """
  Consulta necesidades. Filtros opcionales (keyword): :zona, :tipo,
  :prioridad :estado. El resultado sale ordenado por prioridad.
  """
  def consultar(mapa, filtros \\ []) do
    mapa
    |> Map.values()
    |> Enum.filter(&cumple_filtros?(&1, filtros))
    |> ordenar_por_prioridad()
  end

  @doc "Necesidades pendientes, de la más urgente a la menos urgente."
  def pendientes(mapa), do: consultar(mapa, estado: :pendiente)

  @doc "Ordena por prioridad (crítica primero) y, a igual prioridad, por id."
  def ordenar_por_prioridad(necesidades) do
    Enum.sort_by(necesidades, &{rango(&1.prioridad), &1.id})
  end

  defp rango(prioridad), do: Enum.find_index(@prioridades, &(&1 == prioridad))

  @doc """
  Planifica la atención: recorre las necesidades (ya ordenadas por
  prioridad) y reserva para cada una lo que le falta mientras alcance el
  inventario de su tipo; si no alcanza, la salta y sigue con la siguiente.

  disponibles es %{"agua" => 50, ...}. Devuelve [{id, recurso, cantidad}]
  en orden de atención. Recursiva sobre la lista de necesidades.
  """
  def planificar(necesidades, disponibles), do: planificar(necesidades, disponibles, [])

  # Caso base: no quedan necesidades, se devuelve el plan en orden de atención
  defp planificar([], _disponibles, acumulado), do: Enum.reverse(acumulado)

  # Caso recursivo: si alcanza el inventario se reserva lo que le falta a la
  # necesidad, y en ambos casos se sigue con el resto de la lista

  defp planificar([necesidad | resto], disponibles, acumulado) do
    recurso = Atom.to_string(necesidad.tipo)
    falta = restante(necesidad)
    hay = Map.get(disponibles, recurso, 0)

    if falta > 0 and hay >= falta do
      planificar(resto, Map.put(disponibles, recurso, hay - falta), [
        {necesidad.id, recurso, falta} | acumulado
      ])
    else
      planificar(resto, disponibles, acumulado)
    end
  end

  defp cumple_filtros?(necesidad, filtros) do
    Enum.all?(filtros, fn
      {:zona, valor} -> normalizar(necesidad.zona) == normalizar(valor)
      {:tipo, valor} -> coincide?(necesidad.tipo, valor, @tipos)
      {:prioridad, valor} -> coincide?(necesidad.prioridad, valor, @prioridades)
      {:estado, valor} -> coincide?(necesidad.estado, valor, @estados)
      _otro -> true
    end)
  end

  defp coincide?(actual, valor, validos) do
    case convertir(valor, validos, :invalido) do
      {:ok, atomo} -> atomo == actual
      {:error, _razon} -> false
    end
  end

  #  Conversión a filas de texto
  @doc "Convierte una necesidad en la fila que guarda Almacen."
  def a_fila(necesidad) do
    [
      necesidad.id,
      necesidad.tipo,
      necesidad.descripcion,
      necesidad.cantidad,
      necesidad.zona,
      necesidad.prioridad,
      necesidad.responsable,
      necesidad.estado,
      Enum.map_join(necesidad.asignaciones, ";", fn {codigo, cantidad} ->
        "#{codigo}:#{cantidad}"
      end)
    ]
  end

  @doc "Reconstruye una necesidad desde su fila. Una fila dañada devuelve :error."
  def desde_fila([id, tipo, descripcion, cantidad, zona, prioridad, responsable, estado, asignaciones]) do
    case convertir(tipo, @tipos, :error) do
      {:ok, tipo} ->
        case convertir(prioridad, @prioridades, :error) do
          {:ok, prioridad} ->
            case convertir(estado, @estados, :error) do
              {:ok, estado} ->
                reconstruir(id, tipo, descripcion, cantidad, zona, prioridad, responsable, estado, asignaciones)

              _ ->
                :error
            end

          _ ->
            :error
        end

      _ ->
        :error
    end
  end

  def desde_fila(_otra), do: :error

  # Último paso de desde_fila: la cantidad y las asignaciones del archivo
  defp reconstruir(id, tipo, descripcion, cantidad, zona, prioridad, responsable, estado, asignaciones) do
    case Integer.parse(cantidad) do
      {n, ""} when n > 0 ->
        case decodificar_asignaciones(String.split(asignaciones, ";", trim: true), []) do
          {:ok, asignaciones} ->
            {:ok,
             %Necesidad{
               id: id,
               tipo: tipo,
               descripcion: descripcion,
               cantidad: n,
               zona: zona,
               prioridad: prioridad,
               responsable: responsable,
               estado: estado,
               asignaciones: asignaciones
             }}

          _ ->
            :error
        end

      _ ->
        :error
    end
  end

  # Recursiva sobre la lista de partes "codigo:cantidad".
  # Caso base: no quedan partes, se devuelven las asignaciones decodificadas
  defp decodificar_asignaciones([], acumulado), do: {:ok, Enum.reverse(acumulado)}

  # Caso recursivo: se decodifica la primera parte y se sigue con el resto
  defp decodificar_asignaciones([parte | resto], acumulado) do
    case String.split(parte, ":") do
      [codigo, cantidad] ->
        case Integer.parse(cantidad) do
          {n, ""} when n > 0 -> decodificar_asignaciones(resto, [{codigo, n} | acumulado])
          _ -> :error
        end

      _ ->
        :error
    end
  end

  # Validaciones

  defp convertir(valor, validos, razon) when is_atom(valor) or is_binary(valor) do
    buscado = normalizar(valor)

    case Enum.find(validos, &(Atom.to_string(&1) == buscado)) do
      nil -> {:error, razon}
      atomo -> {:ok, atomo}
    end
  end

  defp convertir(_valor, _validos, razon), do: {:error, razon}

  defp validar_cantidad(cantidad) when is_integer(cantidad) and cantidad > 0, do: :ok
  defp validar_cantidad(_cantidad), do: {:error, :cantidad_invalida}

  defp validar_texto(texto, razon) do
    if is_binary(texto) and String.trim(texto) != "", do: :ok, else: {:error, razon}
  end

  defp validar_opcional(texto) when is_binary(texto), do: :ok
  defp validar_opcional(_otro), do: {:error, :datos_invalidos}

  # Minúsculas, sin tildes y con espacios como guion bajo:
  # "En Atención" -> "en_atencion".
  defp normalizar(texto) do
    texto
    |> to_string()
    |> String.trim()
    |> String.downcase()
    |> :unicode.characters_to_nfd_binary()
    |> String.replace(~r/\p{Mn}/u, "")
    |> String.replace(~r/\s+/, "_")
  end
end
