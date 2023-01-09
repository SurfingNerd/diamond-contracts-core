const fs = require('fs');
const solc = require('solc');

async function compile(dir, contractName) {
  console.log('called compile with ', dir);

  const input = {
    language: 'Solidity',
    sources: {
      '': {
        content: fs.readFileSync(dir + contractName + '.sol').toString()
      }
    },
    settings: {
      optimizer: {
        enabled: true,
        runs: 200
      },
      evmVersion: "istanbul",
      outputSelection: {
        '*': {
          '*': [ 'abi', 'evm.bytecode.object', 'evm.methodIdentifiers' ]
        }
      }
    }
  }

  console.log('contenet read:', input.sources[''].content);

  const compiled = JSON.parse(solc.compile(JSON.stringify(input), function(path) {
    let content;
    try {
      content = fs.readFileSync(dir + path);
    } catch (e) {
      if (e.code == 'ENOENT') {
        try {
          content = fs.readFileSync(dir + '../' + path);
        } catch (e) {
          content = fs.readFileSync(dir + '../node_modules/' + path);
        }
      }
    }
    return {
      contents: content.toString()
    }
  }));

  return compiled.contracts[''][contractName];
}

module.exports = {
  compile
}
