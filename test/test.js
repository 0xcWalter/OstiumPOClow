const exec = require("child_process").exec;
const ethers = require("ethers");
const ABI = ["function arbBlockNumber() external view returns(uint256)"];
const fs = require("fs");

async function testIt() {
  let provider = new ethers.JsonRpcProvider(
    "https://arbitrum-one.public.blastapi.io"
  );
  const contract = new ethers.Contract(
    "0x0000000000000000000000000000000000000064",
    ABI,
    provider
  );
  let blockNumber = (await contract.arbBlockNumber()).toString();
  fs.writeFileSync("test/currentBlock", blockNumber);
  let command = "forge test -vvvv";
  var child = exec(command);
  saveText = "";
  child.stdout.on("data", function (data) {
    saveText = saveText + data;
    console.log(saveText)
  });
}

async function mainLauncher(){
    await testIt();
}

mainLauncher()
