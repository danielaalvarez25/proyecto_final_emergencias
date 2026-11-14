defmodule Mascota do
  @moduledoc """
  Reporte de mascota perdida o encontrada.
  """

  defstruct id: "",
            tipo: :perdida,
            especie: "",
            nombre: "desconocido",
            caracteristicas: "",
            color: "",
            tamano: "",
            zona: "",
            contacto: "",
            estado: :activa,
            coincidencia: nil

  @doc """
  Crea un reporte de mascota en estado activo.

  """
  def crear(id, tipo, especie, nombre, caracteristicas, color, tamano, zona, contacto) do
    %Mascota{
      id: id,
      tipo: tipo,
      especie: especie,
      nombre: nombre,
      caracteristicas: caracteristicas,
      color: color,
      tamano: tamano,
      zona: zona,
      contacto: contacto
    }
  end

  defimpl String.Chars, for: Mascota do
    def to_string(%Mascota{
          id: id,
          tipo: tipo,
          especie: especie,
          nombre: nombre,
          color: color,
          zona: zona,
          estado: estado
        }) do
      "#{id}: #{especie} #{nombre} (#{color}), #{tipo} en #{zona}, estado #{estado}"
    end
  end
end
