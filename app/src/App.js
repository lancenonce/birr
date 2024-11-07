import React, { useState } from "react";
import { ReclaimClient } from "@reclaimprotocol/zk-fetch";

function App() {
  const [proof, setProof] = useState(null);

  const handleUpdateRate = async () => {
    const client = new ReclaimClient(
      "0x99333BC66A1C44B3b835fa9bEA165215969C5ac3",
      "0x7fff39aa07099c8875c0031ce61f066dc727c09f365c169f315c11ddb250bd7c"
    );

    const publicOptions = {
      method: "GET",
      headers: {
        accept: "application/json, text/plain, */*",
      },
    };

    try {
      const proof = await client.zkFetch(
        "https://api.nbe.gov.et/api/get-selected-exchange-rates",
        publicOptions
      );
      setProof(proof);
    } catch (error) {
      console.error("Error fetching proof:", error);
    }
  };

  return (
    <div className="App">
      <header className="App-header">
        <button onClick={handleUpdateRate}>Update Rate</button>
        {proof && <pre>{JSON.stringify(proof, null, 2)}</pre>}
      </header>
    </div>
  );
}

export default App;
