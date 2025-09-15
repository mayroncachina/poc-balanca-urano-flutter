# PoC Balança Urano Bluetooth

Este projeto é uma Prova de Conceito (PoC) para comunicação via Bluetooth com balanças da Urano, modelo [Balança computadora US 31/2 POP-S com adaptador bluetooth](https://www.urano.com.br/produto/balanca-computadora-us-312-pop-s-com-adaptador-bt/).

O objetivo é realizar a conexão Bluetooth com a balança, receber e exibir os dados de pesagem automaticamente.

## Funcionalidades
- Seleção do dispositivo Bluetooth
- Pareamento e conexão automática
- Envio de comandos ENQ para leitura de peso
- Parsing dos dados recebidos (STX/ETX)
- Exibição do peso e log de comunicação

## Requisitos
- Flutter
- Dispositivo Android com Bluetooth
- Balança Urano US 31/2 POP-S com adaptador Bluetooth

## Como usar
1. Instale os pacotes do projeto (`flutter pub get`)
2. Execute o app em um dispositivo Android
3. Selecione a balança Urano na lista de dispositivos Bluetooth
4. Inicie a pesagem e visualize os dados recebidos

---
Projeto para testes internos e validação de integração Bluetooth com balanças Urano.
