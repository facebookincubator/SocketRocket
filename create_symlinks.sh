#!/bin/bash

if [ "$#" -ne 1 ]; then
    echo "Usage: $0 /path/to"
    exit 1
fi

SOURCE_DIR=$1
INCLUDE_DIR="$SOURCE_DIR/include"

mkdir -p "$INCLUDE_DIR"

find "$SOURCE_DIR" -type f -name "*.h" | while read -r file; do
    filename=$(basename "$file")
    symlink_path="$INCLUDE_DIR/$filename"
    if [ ! -e "$symlink_path" ]; then
        ln -s "../$file" "$symlink_path"
        # cp "$file" "$symlink_path"
        echo "Создана ссылка для: $file"
        # Выводим исходный путь файла, на который ссылка указывает
        echo "Исходный путь: $file"
    else
        echo "Ссылка для $file уже существует"
    fi
done

echo "Обработка завершена."
