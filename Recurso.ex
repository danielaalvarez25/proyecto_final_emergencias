defmodule Recurso do
  @moduledoc """
  Recurso disponible en un centro de acopio, albergue o punto de atención.
"""

  defstruct codigo: "",
            nombre: "",
            categoria: "",
            cantidad: 0,
            unidad: "",
            ubicacion: "",
            historial: []

  @doc """
  Crea un recurso sin historial de movimientos.
  """
  def crear(codigo, nombre, categoria, cantidad, unidad, ubicacion) do
    %Recurso{
      codigo: codigo,
      nombre: nombre,
      categoria: categoria,
      cantidad: cantidad,
      unidad: unidad,
      ubicacion: ubicacion
    }
  end

  defimpl String.Chars, for: Recurso do
    def to_string(%Recurso{
          codigo: codigo,
          nombre: nombre,
          cantidad: cantidad,
          unidad: unidad,
          ubicacion: ubicacion
        }) do
      "#{codigo}: #{nombre}, #{cantidad} #{unidad} en #{ubicacion}"
    end
  end
end
