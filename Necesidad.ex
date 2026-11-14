defmodule Necesidad do
  @moduledoc """
  Solicitud de ayuda puntual asociada a una zona.
  """

  defstruct id: "",
            tipo: :otra,
            descripcion: "",
            cantidad: 0,
            zona: "",
            prioridad: :media,
            responsable: "",
            estado: :pendiente,
            asignaciones: []

  @doc """
  Crea una necesidad en estado pendiente y sin recursos asignados.


  """
  def crear(id, tipo, cantidad, zona, prioridad, responsable \\ "", descripcion \\ "") do
    %Necesidad{
      id: id,
      tipo: tipo,
      descripcion: descripcion,
      cantidad: cantidad,
      zona: zona,
      prioridad: prioridad,
      responsable: responsable
    }
  end

  defimpl String.Chars, for: Necesidad do
    def to_string(%Necesidad{
          id: id,
          tipo: tipo,
          cantidad: cantidad,
          zona: zona,
          prioridad: prioridad,
          estado: estado
        }) do
      "#{id}: #{tipo} (#{cantidad}), zona #{zona}, prioridad #{prioridad}, estado #{estado}"
    end
  end
end
