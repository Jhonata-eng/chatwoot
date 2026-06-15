/* global axios */
import ApiClient from '../ApiClient';

class CaptainLocalModels extends ApiClient {
  constructor() {
    super('captain/local_models', { accountScoped: true });
  }

  get(purpose = null) {
    const params = purpose ? { purpose } : {};
    return axios.get(this.url, { params });
  }
}

export default new CaptainLocalModels();