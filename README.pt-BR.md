# Script de Pós-Instalação Fedora 💻

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Bash](https://img.shields.io/badge/Bash-4.0+-blue.svg)](https://www.gnu.org/software/bash/)
[![Fedora](https://img.shields.io/badge/Fedora-39+-blue.svg)](https://getfedora.org/)
[![Version](https://img.shields.io/badge/Version-2.0.0-green.svg)]()

> 🚀 **Configuração moderna e interativa de pós-instalação para Fedora Linux** - Transforme sua nova instalação Fedora em uma estação de trabalho de desenvolvimento completa com apenas alguns cliques!

## ✨ Funcionalidades

- 🔍 **Detecção Automática de Versão do Fedora** - Funciona perfeitamente em todas as versões do Fedora (39+)
- 🎯 **Sistema de Menu Interativo** - Interface amigável com opções claras
- 🛡️ **Tratamento Abrangente de Erros** - Logging robusto e recuperação de falhas
- 📦 **Gerenciamento Moderno de Pacotes** - Integração DNF + Flatpak
- 🎨 **Fontes de Desenvolvimento** - Fira Code, JetBrains Mono e mais
- 🛠️ **Ferramentas de Desenvolvimento** - VS Code, Git, Node.js, Python e utilitários essenciais
- 🎵 **Aplicativos Multimídia** - Música, vídeo e apps de produtividade via Flatpak
- 🔧 **Extensões GNOME** - AppIndicator, Caffeine, GSConnect e mais
- 🧹 **Limpeza do Sistema** - Remoção de bloatware e otimização de performance
- 📋 **Logging Detalhado** - Logs completos de instalação para troubleshooting

## 🎯 O Que Está Incluído

### Atualizações e Limpeza do Sistema
- ✅ Atualizações de pacotes do sistema
- 🗑️ Remoção de bloatware (Rhythmbox, Totem, etc.)
- 📚 Repositórios adicionais (RPM Fusion, COPR)

### Ambiente de Desenvolvimento
- 💻 **Visual Studio Code** - Editor de código poderoso da Microsoft
- 🐙 **Git** - Sistema de controle de versão
- 🟢 **Node.js & NPM** - Runtime JavaScript e gerenciador de pacotes
- 🐍 **Python** - Linguagem de programação com pip
- 🔧 **Ferramentas Essenciais** - GParted, GameMode e mais

### Fontes e Tipografia
- 🔥 **Fira Code** - Fonte monoespaçada com ligaduras de programação
- ✈️ **JetBrains Mono** - Fonte monoespaçada cuidadosamente criada

### Melhorias do Desktop GNOME
- 🔌 **Suporte AppIndicator** - Ícones de bandeja para várias aplicações
- ☕ **Caffeine** - Previne bloqueio de tela e suspensão
- 📱 **GSConnect** - Integração KDE Connect para dispositivos Android
- 🎛️ **GNOME Tweaks** - Customização avançada do desktop

### Aplicativos Flatpak
- 🧩 **Extension Manager** - Gerencie extensões GNOME facilmente
- 🔒 **Flatseal** - Gerencie permissões Flatpak
- 🎵 **Decibels** - Tocador de áudio para GNOME
- 🔄 **Converter** - Ferramenta de conversão de unidades
- 🌙 **Insomnia** - Cliente REST API
- 🗄️ **DBeaver** - Ferramenta universal de banco de dados

## 🚀 Início Rápido

### Pré-requisitos
- ✅ Instalação fresca do Fedora (39+)
- ✅ Conexão com internet
- ✅ Privilégios sudo
- ✅ Bash 4.0+

### Instalação e Uso

1. **Baixe o script:**
   ```bash
   git clone https://github.com/EmanuProds/post-installation_fedora.git
   cd post-installation_fedora
   ```

2. **Torne-o executável:**
   ```bash
   chmod +x fedoraPI.sh
   ```

3. **Execute o script:**
   ```bash
   ./fedoraPI.sh
   ```

4. **Siga o menu interativo** para escolher o que instalar!

## 📖 Opções do Menu

O script fornece um sistema de menu **gráfico intuitivo** usando `dialog`:

1. **Atualização e Limpeza do Sistema** - Atualizar pacotes, remover bloatware, adicionar repositórios
2. **Instalar Fontes** - Fontes de desenvolvimento (Fira Code, JetBrains Mono)
3. **Instalar Ferramentas de Desenvolvimento** - VS Code, Git, Node.js e utilitários essenciais
4. **Configurar Flatpak e Instalar Apps** - Ecossistema Flatpak e aplicações
5. **Executar Configuração Completa** - Instalar tudo automaticamente
6. **Sair** - Sair do script

### Recursos da Interface
- 🎯 **Diálogos de confirmação** para todas as operações
- 📊 **Barras de progresso** durante as instalações
- ✅ **Notificações de sucesso** após cada tarefa
- 🚫 **Suporte a Cancelar/Escape** para sair a qualquer momento
- 🖥️ **GUI baseada em terminal** - funciona em qualquer ambiente de terminal

## 🔧 Detalhes Técnicos

### Detecção Automática de Versão
O script detecta automaticamente sua versão do Fedora e configura repositórios adequadamente:

- **Fedora 39-41**: Modo de compatibilidade legado
- **Fedora 42+**: Suporte completo a funcionalidades
- **Versões futuras**: Adaptação automática

### Gerenciamento de Repositórios
- **RPM Fusion**: Repositórios Free e Non-Free
- **Microsoft VS Code**: Repositório oficial
- **COPR**: Repositórios da comunidade (linuxtoys)

### Tratamento de Erros
- Logging abrangente para `/tmp/fedora_pi_YYYYMMDD_HHMMSS.log`
- Tratamento gracioso de falhas com mensagens de erro detalhadas
- Verificações de conectividade de rede
- Validação de disponibilidade de repositórios

### Recursos de Segurança
- Execução não-root (usa sudo quando necessário)
- Verificação de chaves GPG para repositórios
- Remoção segura de pacotes (verifica antes de remover)

## 📋 Requisitos

### Requisitos do Sistema
- **SO**: Fedora Linux 39 ou posterior
- **RAM**: 4GB mínimo (8GB recomendado)
- **Armazenamento**: 10GB de espaço livre
- **Rede**: Conexão ativa com internet

### Dependências de Software
- `bash` 4.0+
- privilégios `sudo`
- gerenciador de pacotes `dnf`
- `curl` para validação de repositórios
- `flatpak` (instalado automaticamente se ausente)

## 🐛 Solução de Problemas

### Problemas Comuns

**"Nenhuma conexão com internet detectada"**
- Verifique suas configurações de rede
- Garanta que a resolução DNS está funcionando
- Tente `ping 8.8.8.8` para testar conectividade

**"Repositório não disponível"**
- O script trata automaticamente repositórios indisponíveis
- Verifique o arquivo de log para detalhes
- Algumas funcionalidades podem ser limitadas para versões antigas do Fedora

**"Permissão negada"**
- Garanta que está executando como usuário comum (não root)
- Verifique se o sudo está configurado corretamente

### Arquivos de Log
Todas as operações são registradas em `/tmp/fedora_pi_*.log`. Verifique este arquivo para informações detalhadas de erro.

### Obtendo Ajuda
1. Verifique o arquivo de log para detalhes de erro
2. Garanta que todos os pré-requisitos estão atendidos
3. Tente executar opções individuais do menu em vez da configuração completa

## 📄 Licença

Este projeto está licenciado sob a Licença MIT - veja o arquivo [LICENSE](LICENSE) para detalhes.
