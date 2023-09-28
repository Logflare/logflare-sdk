interface Options {
  sourceToken: string;
  apiKey: string;
  apiUrl?: string;
  // onError is an optional callback function to handle any errors returned by logflare
  onError?: (
    payload: {
      batch: object[];
    },
    err: Error
  ) => void;
}

class NetworkError extends Error {
  name = "NetworkError";

  constructor(
    message: string,
    public response: Response,
    public data: unknown
  ) {
    super(message);
  }
}

export class LogflareHttpClient {
  protected readonly sourceToken: string;
  protected readonly apiKey: string;
  protected readonly apiUrl: string = "https://api.logflare.app";
  protected readonly onError: Options["onError"]

  public constructor(options: Options) {
    const { sourceToken, apiKey } = options;
    if (!sourceToken) {
      throw "Logflare API source token is NOT configured!";
    }
    if (!apiKey) {
      throw "Logflare API logging transport api key is NOT configured!";
    }

    this.sourceToken = sourceToken;
    this.apiKey = apiKey;
    if (options.apiUrl) {
      this.apiUrl = options.apiUrl;
    }
    this.onError = options.onError;
  }

  public async sendEvent(event: object) {
    return this.sendEvents([event]);
  }

  public async sendEvents(batch: object[]) {
    const path = `/api/logs?api_key=${this.apiKey}&source=${this.sourceToken}`;
    const payload = { batch };
    try {
      const url = new URL(path, this.apiUrl);

      const response = await fetch(url.toString(), {
        body: JSON.stringify(payload),
        method: "POST",
        headers: {
          Accept: "application/json, text/plain, */*",
          "Content-Type": "application/json",
        },
      });

      const data = await response.json();

      if (!response.ok) {
        throw new NetworkError(
          `Network response was not ok for "${url}"`,
          response,
          data
        );
      }

      return data;
    } catch (e) {
      if (e && e instanceof Error) {
        if (e instanceof NetworkError && e.response) {
          console.error(
            `Logflare API request failed with ${
              e.response.status
            } status: ${JSON.stringify(e.data)}`
          );
        } else {
          console.error(e.message);
        }
        this.onError?.(payload, e);
      }

      return e;
    }
  }
}
