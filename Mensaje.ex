defmodule Mensaje do
  @moduledoc """
  Mensaje dirigido a una persona o familia.
"""

  defstruct id: "",
            fecha: "",
            remitente: "",
            destinatario: "",
            contenido: "",
            estado: :pendiente

  @doc """
  Crea un mensaje pendiente de entrega.
  """
  def crear(id, fecha, remitente, destinatario, contenido, estado \\ :pendiente) do
    %Mensaje{
      id: id,
      fecha: fecha,
      remitente: remitente,
      destinatario: destinatario,
      contenido: contenido,
      estado: estado
    }
  end

  defimpl String.Chars, for: Mensaje do
    def to_string(%Mensaje{
          fecha: fecha,
          remitente: remitente,
          destinatario: destinatario,
          contenido: contenido,
          estado: estado
        }) do
      "#{fecha} #{remitente} -> #{destinatario}: #{contenido} (#{estado})"
    end
  end
end
