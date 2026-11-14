defmodule PuntoAtencion do
  @moduledoc """
  Punto de atención dentro de un sector (

  - nombre: nombre del punto de atención
  - personas_estimadas: personas estimadas en el punto
  """

  defstruct nombre: "",
            personas_estimadas: 0

  @doc """
  Crea un punto de atención.
  """
  def crear(nombre, personas_estimadas \\ 0) do
    %PuntoAtencion{
      nombre: nombre,
      personas_estimadas: personas_estimadas
    }
  end

  defimpl String.Chars, for: PuntoAtencion do
    def to_string(%PuntoAtencion{nombre: nombre, personas_estimadas: personas_estimadas}) do
      "#{nombre}, #{personas_estimadas} personas"
    end
  end
end
